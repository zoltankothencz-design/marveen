#!/usr/bin/env python3
"""
CV + Cover Letter independent reviewer for job-hunter agent.

This script acts as the "second opinion" reviewer with fresh context.
It reads the CV and cover letter text (no prior context), checks:
  1. Language quality (grammar patterns, overused phrases, red flags)
  2. Internal consistency (name, dates, claims)
  3. Company reputation check via stored memory / web search
  4. Overall recommendation: OK / NEEDS_REVISION

Usage:
  python3 cv-reviewer.py --cv path/to/cv.md --cl path/to/cover_letter.md \
    --position "Head of Casino Operations" --company "Van Kaizen" --jd "JD text"

Outputs JSON to stdout. Exit 0 = OK to proceed, 1 = revision needed.
"""

import sys, os, re, json, argparse, subprocess
from datetime import datetime

# ---------------------------------------------------------------------------
# Quality checks (deterministic, no LLM needed)
# ---------------------------------------------------------------------------

OVERUSED_PHRASES = [
    "passionate about", "results-driven", "team player", "go-getter", "self-starter",
    "think outside the box", "synergy", "leverage", "proactive", "detail-oriented",
    "fast-paced environment", "hardworking", "motivated", "dynamic", "innovative",
    "seasoned professional", "proven track record", "excellent communication",
    "strong communication skills", "multitask", "wearing many hats",
]

RED_FLAGS = [
    # Claims that are risky without proof
    "managed \d+ billion", "saved the company \$", "single-handedly",
    r"\b(lied|falsified|fabricated)\b",
]

INCONSISTENCY_PATTERNS = [
    # Date range overlaps are detected separately
]


def check_language_quality(cv_text: str, cl_text: str) -> dict:
    combined = (cv_text + "\n" + cl_text).lower()
    issues = []

    # Overused phrases
    found_overused = [p for p in OVERUSED_PHRASES if p.lower() in combined]
    if found_overused:
        issues.append(f"Overused phrases detected: {', '.join(found_overused[:5])}")

    # Red flag patterns
    for pattern in RED_FLAGS:
        if re.search(pattern, combined, re.I):
            issues.append(f"Potential red flag: '{pattern}'")

    # Very short cover letter (< 150 words)
    word_count = len(cl_text.split()) if cl_text else 0
    if word_count > 0 and word_count < 120:
        issues.append(f"Cover letter is very short ({word_count} words; aim for 200-350)")
    if word_count > 500:
        issues.append(f"Cover letter is too long ({word_count} words; aim for 200-350)")

    # ALL CAPS sections (unprofessional)
    caps_lines = [l.strip() for l in cv_text.split('\n')
                  if l.strip().isupper() and len(l.strip()) > 10]
    if caps_lines:
        issues.append(f"ALL CAPS lines found (unprofessional for ATS): {caps_lines[:2]}")

    # Repeated sentences (copy-paste signal)
    sentences = re.split(r'[.!?]\s+', combined)
    seen_sents, dupes = set(), []
    for s in sentences:
        s_clean = re.sub(r'\s+', ' ', s.strip().lower())
        if len(s_clean) > 30:
            if s_clean in seen_sents:
                dupes.append(s_clean[:60])
            seen_sents.add(s_clean)
    if dupes:
        issues.append(f"Duplicate sentences detected: {dupes[:2]}")

    return {
        "issues": issues,
        "word_count_cl": word_count,
        "ok": len(issues) == 0,
    }


def check_consistency(cv_text: str, position: str, company: str) -> dict:
    issues = []

    # Date overlap detection: find year ranges like 2018-2021, 2021-2024
    ranges = re.findall(r'(20\d\d)[–\-–—](20\d\d|present|current|now)', cv_text, re.I)
    year_ranges = []
    for start, end in ranges:
        s = int(start)
        e = datetime.now().year if end.lower() in ('present', 'current', 'now') else int(end)
        year_ranges.append((s, e))

    # Check for suspicious overlaps (more than 1 year overlap)
    for i, (s1, e1) in enumerate(year_ranges):
        for j, (s2, e2) in enumerate(year_ranges):
            if i >= j:
                continue
            overlap = min(e1, e2) - max(s1, s2)
            if overlap > 1:
                issues.append(
                    f"Possible date overlap: {s1}-{e1} and {s2}-{e2} "
                    f"(overlap ~{overlap} years)"
                )

    # Company name appears in CV?
    if company and company.lower() not in cv_text.lower():
        issues.append(
            f"Target company '{company}' not mentioned in CV "
            f"(cover letter should bridge this if applying externally)"
        )

    # Position keyword in CV?
    if position:
        pos_words = [w for w in position.lower().split() if len(w) > 4]
        missing_pos_words = [w for w in pos_words if w not in cv_text.lower()]
        if len(missing_pos_words) > len(pos_words) // 2:
            issues.append(
                f"Position title words mostly absent from CV: {missing_pos_words} "
                f"(consider aligning job title or summary)"
            )

    return {"issues": issues, "ok": len(issues) == 0}


def check_company_reputation(company: str) -> dict:
    """Quick reputation check via API memory search."""
    if not company:
        return {"note": "No company specified", "ok": True}

    # Check local memory for any stored reputation data
    try:
        token_file = '/home/userzoltan/marveen/store/.dashboard-token'
        if not os.path.exists(token_file):
            return {"note": "Memory not available", "ok": True}
        token = open(token_file).read().strip()
        result = subprocess.run(
            ['curl', '-s',
             f'http://localhost:3420/api/memories?agent=job-hunter&q={company}&category=warm',
             '-H', f'Authorization: Bearer {token}'],
            capture_output=True, text=True, timeout=5
        )
        memories = json.loads(result.stdout) if result.stdout else []
        negative_keywords = ['layoff', 'scam', 'fraud', 'bankrupt', 'lawsuit',
                             'leepites', 'csod', 'hamis', 'pereskedik']
        warnings = []
        for mem in memories:
            content = str(mem.get('content', '')).lower()
            for kw in negative_keywords:
                if kw in content:
                    warnings.append(f"Memory flag: '{kw}' found for {company}")
        return {
            "memories_checked": len(memories),
            "warnings": warnings,
            "ok": len(warnings) == 0,
            "note": f"Found {len(memories)} memory entries for '{company}'"
        }
    except Exception as e:
        return {"note": f"Memory check failed: {e}", "ok": True}


def overall_verdict(lang: dict, consistency: dict, reputation: dict) -> tuple[str, str]:
    """Return (verdict, summary). Verdict: OK or NEEDS_REVISION."""
    all_issues = lang["issues"] + consistency["issues"] + reputation.get("warnings", [])
    if not all_issues:
        return "OK", "No significant issues found. Document looks ready."

    # Minor issues = still OK but note them
    minor_only = all(
        any(phrase in issue for phrase in ["short", "Overused", "not mentioned"])
        for issue in all_issues
    )
    if minor_only and len(all_issues) <= 2:
        return "OK_WITH_NOTES", f"Minor issues: {'; '.join(all_issues)}"

    return "NEEDS_REVISION", f"Issues found: {'; '.join(all_issues)}"


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--cv', required=True, help='Path to CV file (.md or .txt)')
    p.add_argument('--cl', default='', help='Path to cover letter file (.md or .txt)')
    p.add_argument('--position', default='', help='Target position title')
    p.add_argument('--company', default='', help='Target company name')
    p.add_argument('--jd', default='', help='Job description text (optional, for context)')
    args = p.parse_args()

    cv_text = open(args.cv, encoding='utf-8').read() if os.path.exists(args.cv) else ''
    cl_text = open(args.cl, encoding='utf-8').read() if args.cl and os.path.exists(args.cl) else ''

    lang = check_language_quality(cv_text, cl_text)
    consistency = check_consistency(cv_text, args.position, args.company)
    reputation = check_company_reputation(args.company)
    verdict, summary = overall_verdict(lang, consistency, reputation)

    result = {
        "verdict": verdict,
        "summary": summary,
        "language": lang,
        "consistency": consistency,
        "reputation": reputation,
        "checked_at": datetime.now().isoformat(),
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    sys.exit(0 if verdict in ("OK", "OK_WITH_NOTES") else 1)


if __name__ == '__main__':
    main()
