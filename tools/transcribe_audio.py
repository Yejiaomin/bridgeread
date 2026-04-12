"""
Transcribe original book audio with word-level timestamps using Whisper.
Match against OCR text to find accurate pageStartMs.
Uses full-page text matching to handle repeated phrases correctly.
"""
import whisper
import json
import sys
import os
import re
import glob

ASSETS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'assets')
LESSONS_DIR = os.path.join(ASSETS, 'lessons')
OCR_DIR = os.path.join(LESSONS_DIR, '_ocr')

def transcribe(audio_path):
    """Transcribe audio file and return word-level timestamps."""
    print(f"Loading Whisper model (base)...")
    model = whisper.load_model("base")
    print(f"Transcribing: {audio_path}")
    result = model.transcribe(audio_path, word_timestamps=True, language="en")

    words = []
    for seg in result["segments"]:
        for w in seg.get("words", []):
            words.append({
                "word": w["word"].strip(),
                "start": round(w["start"] * 1000),
                "end": round(w["end"] * 1000),
            })
    return words

def clean_word(w):
    """Normalize a word for comparison."""
    return re.sub(r"[^a-z']", "", w.lower())

def extract_words(text):
    """Extract meaningful words from text, filtering OCR noise."""
    words = re.findall(r"[a-zA-Z']{2,}", text)
    skip = {'woof', 'meow', 'moo', 'oink', 'quack', 'oh', 'ah'}
    return [w.lower() for w in words if w.lower() not in skip]

def match_page_text(transcript_words, page_text, search_from=0):
    """Match page text against transcript. Returns (start_ms, end_index).

    Finds the best sequential match of page words in the transcript,
    starting from search_from. Returns the start timestamp of the first
    matched word and the index after the last matched word.
    """
    page_words = extract_words(page_text)
    if not page_words:
        return None, search_from

    best_start_ms = None
    best_end_idx = search_from

    # Try to find a sequential match of page words in transcript
    # We don't require ALL words to match (Whisper may miss some),
    # but we need a good sequential match

    # Strategy: find the first 2-3 content words that are unique enough
    # Then verify by checking subsequent words

    for start_i in range(search_from, len(transcript_words)):
        tw = clean_word(transcript_words[start_i]["word"])
        if tw != page_words[0]:
            continue

        # Found potential start - try to match rest of page words
        matched = 1
        t_idx = start_i + 1
        p_idx = 1
        last_matched_t_idx = start_i

        while p_idx < len(page_words) and t_idx < len(transcript_words):
            tw = clean_word(transcript_words[t_idx]["word"])
            if tw == page_words[p_idx]:
                matched += 1
                last_matched_t_idx = t_idx
                p_idx += 1
                t_idx += 1
            else:
                # Allow skipping up to 2 transcript words (Whisper artifacts)
                t_idx += 1
                if t_idx - last_matched_t_idx > 3:
                    # Too many skips, try next page word
                    p_idx += 1
                    t_idx = last_matched_t_idx + 1

        # Need at least 60% match
        match_ratio = matched / len(page_words)
        if match_ratio >= 0.5 and matched >= 2:
            best_start_ms = transcript_words[start_i]["start"]
            best_end_idx = last_matched_t_idx + 1
            break

    return best_start_ms, best_end_idx

def find_ocr_file(lesson):
    """Find the OCR JSON file for a lesson."""
    lesson_id = lesson.get("id", "")
    # e.g. "biscuit_book1_day1" -> base="biscuit_book1", series="biscuit"
    # e.g. "biscuit_baby_book2_day1" -> base="biscuit_baby_book2", series="biscuit_baby"
    base_id = lesson_id.rsplit("_day", 1)[0]
    series_id = base_id.rsplit("_book", 1)[0]

    # Only match OCR files that belong to this specific book/series
    candidates = [
        f"{base_id}_ocr.json",     # e.g. biscuit_book1_ocr.json
        f"{series_id}_ocr.json",   # e.g. biscuit_ocr.json (for series "biscuit")
    ]

    for c in candidates:
        p = os.path.join(OCR_DIR, c)
        if os.path.exists(p):
            return p
    return None

def process_book(lesson_path):
    """Process a lesson JSON: transcribe audio and update pageStartMs."""
    with open(lesson_path, 'r', encoding='utf-8') as f:
        lesson = json.load(f)

    audio_rel = lesson.get("originalAudio", "")
    if not audio_rel:
        print(f"  No originalAudio, skipping")
        return

    audio_path = os.path.join(ASSETS, audio_rel)
    if not os.path.exists(audio_path):
        print(f"  Audio not found: {audio_path}, skipping")
        return

    # Find OCR data
    ocr_path = find_ocr_file(lesson)
    ocr_texts = {}
    if ocr_path:
        with open(ocr_path, 'r', encoding='utf-8') as f:
            ocr_data = json.load(f)
        for op in ocr_data.get("pages", []):
            img = op.get("image", "")
            ocr_texts[img] = op.get("en", "")
        print(f"  Using OCR data from {os.path.basename(ocr_path)}")
    else:
        print(f"  No OCR data, using narrativeEN")

    # Transcribe
    words = transcribe(audio_path)
    print(f"  Got {len(words)} words")

    # Print word timestamps
    print("\n  === Word timestamps ===")
    for w in words:
        print(f"    {w['start']:>7}ms - {w['end']:>7}ms : {w['word']}")
    print()

    pages = lesson["pages"]
    search_from = 0
    updated = 0
    results = []

    for i, page in enumerate(pages):
        img_asset = page.get("imageAsset", "")
        base_name = os.path.splitext(os.path.basename(img_asset))[0]

        # Get match text: prefer OCR, fallback to narrativeEN
        match_text = None
        if ocr_texts:
            for ocr_img, ocr_text in ocr_texts.items():
                if base_name in ocr_img:
                    match_text = ocr_text
                    break
        if not match_text:
            match_text = page.get("narrativeEN", "")

        if not match_text or not match_text.strip():
            results.append(f"  Page {i} ({base_name}): no text, skipping")
            continue

        content_words = extract_words(match_text)
        if not content_words:
            results.append(f"  Page {i} ({base_name}): no matchable words, skipping")
            continue

        start_ms, end_idx = match_page_text(words, match_text, search_from)

        # Fallback: if full text fails, try last half (unique content)
        if start_ms is None:
            content = extract_words(match_text)
            if len(content) > 3:
                half_text = " ".join(content[len(content)//2:])
                start_ms2, end_idx2 = match_page_text(words, half_text, search_from)
                if start_ms2 is not None:
                    # Found via fallback - but we want the START of this page,
                    # so look backward for a gap (>1s silence) before this match
                    look_back = start_ms2
                    for wi in range(end_idx2 - 1, max(search_from - 1, -1), -1):
                        if wi > 0:
                            gap = words[wi]["start"] - words[wi-1]["end"]
                            if gap > 1000:
                                look_back = words[wi]["start"]
                                break
                            look_back = words[wi]["start"]
                    start_ms = look_back
                    end_idx = end_idx2

        if start_ms is not None:
            old_start = page.get("pageStartMs")
            if old_start is None and i == 0:
                results.append(f"  Page {i} ({base_name}): cover, skipping")
                search_from = end_idx  # Still advance past cover audio
                continue

            page["pageStartMs"] = start_ms
            search_from = end_idx  # Skip past ALL of this page's audio
            status = "CHANGED" if old_start != start_ms else "ok"
            results.append(f"  Page {i} ({base_name}): {old_start} -> {start_ms} [{status}]")
            if old_start != start_ms:
                updated += 1
        else:
            results.append(f"  Page {i} ({base_name}): NO MATCH for '{match_text[:50]}'")

    for r in results:
        print(r)

    if updated > 0:
        with open(lesson_path, 'w', encoding='utf-8') as f:
            json.dump(lesson, f, ensure_ascii=False, indent=2)
        print(f"\n  >>> Updated {updated} pages in {os.path.basename(lesson_path)}")
    else:
        print(f"\n  No updates needed for {os.path.basename(lesson_path)}")

def main():
    if len(sys.argv) > 1:
        process_book(sys.argv[1])
    else:
        for f in sorted(glob.glob(os.path.join(LESSONS_DIR, '*_day1.json'))):
            print(f"\n{'='*60}")
            print(f"Processing: {os.path.basename(f)}")
            print('='*60)
            process_book(f)

if __name__ == "__main__":
    main()
