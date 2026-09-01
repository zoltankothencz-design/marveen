#!/usr/bin/env python3
"""
CV PDF pipeline for job-hunter agent.

Usage:
  python3 cv-pdf-pipeline.py --cv path/to/cv.md --jd "Job description text" --out /mnt/c/JOB/output.pdf
  python3 cv-pdf-pipeline.py --cv path/to/cv.md --jd-file path/to/jd.txt --out output.pdf [--max-iter 3]

Steps:
  1. Render markdown CV to styled HTML
  2. Convert HTML to PDF via weasyprint
  3. Read back PDF text (pdfplumber)
  4. Check page count (format) and ATS keyword coverage
  5. If issues: report them; caller decides whether to re-generate
  6. Print JSON result to stdout

Exit codes:
  0 = OK (within acceptable limits)
  1 = Soft warning (ATS coverage low but not critical, or >2 pages)
  2 = Hard fail (PDF could not be generated)
"""

import sys, os, re, json, argparse, textwrap

# ---------------------------------------------------------------------------
# HTML CV template (ATS-friendly: single-column, semantic, readable fonts)
# ---------------------------------------------------------------------------
CSS = """
@page { size: A4; margin: 18mm 18mm 18mm 18mm; }
body {
    font-family: "Arial", "Helvetica", sans-serif;
    font-size: 10.5pt;
    line-height: 1.45;
    color: #111;
    max-width: 100%;
}
h1 { font-size: 18pt; margin: 0 0 2pt 0; color: #1a1a2e; }
h2 { font-size: 11.5pt; border-bottom: 1.5pt solid #1a1a2e;
     margin: 12pt 0 4pt 0; padding-bottom: 2pt; color: #1a1a2e; text-transform: uppercase; letter-spacing: 0.05em; }
h3 { font-size: 10.5pt; margin: 8pt 0 2pt 0; }
p  { margin: 2pt 0 4pt 0; }
ul { margin: 2pt 0 4pt 1em; padding: 0; }
li { margin-bottom: 2pt; }
a  { color: #1a1a2e; text-decoration: none; }
.contact { font-size: 9.5pt; color: #444; margin-bottom: 8pt; }
hr { border: none; border-top: 0.5pt solid #ccc; margin: 6pt 0; }
"""

HTML_TMPL = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<style>{css}</style>
</head>
<body>
{body}
</body>
</html>
"""


def md_to_html(md_text: str) -> str:
    """Convert markdown to HTML. Uses markdown lib if available, else minimal regex."""
    try:
        import markdown as md_lib
        return md_lib.markdown(md_text, extensions=["extra", "nl2br"])
    except ImportError:
        pass
    # Minimal fallback regex converter
    html = md_text
    # Headers
    html = re.sub(r'^# (.+)$', r'<h1>\1</h1>', html, flags=re.M)
    html = re.sub(r'^## (.+)$', r'<h2>\1</h2>', html, flags=re.M)
    html = re.sub(r'^### (.+)$', r'<h3>\1</h3>', html, flags=re.M)
    # Bold
    html = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', html)
    # Bullet lists
    lines, out, in_ul = html.split('\n'), [], False
    for line in lines:
        if re.match(r'^[-*] (.+)', line):
            if not in_ul:
                out.append('<ul>'); in_ul = True
            out.append('<li>' + re.sub(r'^[-*] ', '', line) + '</li>')
        else:
            if in_ul:
                out.append('</ul>'); in_ul = False
            stripped = line.strip()
            if stripped and not stripped.startswith('<h'):
                out.append('<p>' + stripped + '</p>')
            else:
                out.append(line)
    if in_ul:
        out.append('</ul>')
    return '\n'.join(out)


def generate_pdf(md_path: str, out_path: str) -> bool:
    """Render markdown CV to PDF. Returns True on success."""
    with open(md_path, encoding='utf-8') as f:
        md_text = f.read()
    body = md_to_html(md_text)
    full_html = HTML_TMPL.format(css=CSS, body=body)
    html_path = out_path.replace('.pdf', '_tmp.html')
    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(full_html)
    try:
        from weasyprint import HTML
        HTML(filename=html_path).write_pdf(out_path)
        os.unlink(html_path)
        return True
    except Exception as e:
        print(f"[ERROR] weasyprint failed: {e}", file=sys.stderr)
        return False


def read_pdf_text(pdf_path: str) -> str:
    """Extract text layer from PDF."""
    try:
        import pdfplumber
        text_parts = []
        with pdfplumber.open(pdf_path) as pdf:
            for page in pdf.pages:
                t = page.extract_text()
                if t:
                    text_parts.append(t)
        return '\n'.join(text_parts)
    except Exception as e:
        print(f"[WARN] pdfplumber failed: {e}", file=sys.stderr)
        return ""


def get_page_count(pdf_path: str) -> int:
    """Return number of pages in PDF."""
    try:
        import pdfplumber
        with pdfplumber.open(pdf_path) as pdf:
            return len(pdf.pages)
    except Exception:
        return -1


def extract_keywords(jd_text: str) -> list[str]:
    """Extract meaningful keywords from job description."""
    # Remove punctuation, lowercase, split
    words = re.findall(r'[a-zA-Z][a-zA-Z\-]{3,}', jd_text.lower())
    # Common stopwords to skip
    stops = {
        # function words
        'with','that','this','have','will','from','they','your','their',
        'been','more','also','which','about','would','other','into','than',
        'some','then','when','what','where','there','these','those','should',
        'could','must','very','well','each','both','such','after','before',
        'while','being','doing','having','using','making','working','looking',
        'seeking','able','team','role','work','join','help','great','good',
        'best','high','strong','years','year','experience','candidate','position',
        'company','business','please','include','including','ensure','within',
        'across','through','between','without','against','under','following',
        # generic adjectives/adverbs not useful for ATS
        'ideal','preferred','highly','valued','knowledge','essential','required',
        'preferred','excellent','proven','demonstrated','solid','deep','broad',
        'relevant','related','based','ideally','strong','familiarity','proficient',
        'outstanding','exceptional','leading','growing','exciting','dynamic',
        'passionate','motivated','driven','dedicated','innovative','creative',
        'detail','oriented','fast','paced','environment','opportunity','apply',
        'responsible','benefits','bonus','salary','competitive','package','offer',
        'location','remote','hybrid','onsite','office','relocation','travel',
        # filler job description phrases
        'looking','seeking','want','need','requires','require','offer','offering',
        'join','opportunity','excited','thrive','equal','employer','diversity',
    }
    # Keep unique, meaningful words
    seen, keywords = set(), []
    for w in words:
        if w not in stops and w not in seen and len(w) > 3:
            seen.add(w)
            keywords.append(w)
    # Extract 2-gram phrases -- only when BOTH tokens are meaningful (not stopwords, 5+ chars)
    tokens = jd_text.lower().split()
    tokens_clean = [re.sub(r'[^a-z]', '', t) for t in tokens]
    for i in range(len(tokens_clean) - 1):
        t0, t1 = tokens_clean[i], tokens_clean[i+1]
        if (len(t0) >= 5 and len(t1) >= 5
                and t0 not in stops and t1 not in stops):
            bigram = f"{t0} {t1}"
            if bigram not in seen:
                seen.add(bigram)
                keywords.append(bigram)
    return keywords[:80]  # cap at 80


def check_ats(pdf_text: str, jd_text: str) -> dict:
    """Check ATS keyword coverage. Returns dict with score and missing keywords."""
    if not jd_text.strip():
        return {"score": None, "missing": [], "note": "No JD provided"}
    keywords = extract_keywords(jd_text)
    pdf_lower = pdf_text.lower()
    found, missing = [], []
    for kw in keywords:
        if kw in pdf_lower:
            found.append(kw)
        else:
            missing.append(kw)
    score = round(len(found) / max(len(keywords), 1) * 100, 1)
    # Return top-15 missing (most impactful for the agent to consider)
    return {
        "score": score,
        "found_count": len(found),
        "total_keywords": len(keywords),
        "missing_top15": missing[:15],
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--cv', required=True, help='Path to CV markdown file')
    p.add_argument('--jd', default='', help='Job description text (inline)')
    p.add_argument('--jd-file', default='', help='Path to job description text file')
    p.add_argument('--out', required=True, help='Output PDF path')
    p.add_argument('--max-iter', type=int, default=1, help='Max PDF generation iterations (for caller loop)')
    args = p.parse_args()

    jd_text = args.jd
    if args.jd_file and os.path.exists(args.jd_file):
        with open(args.jd_file, encoding='utf-8') as f:
            jd_text = f.read()

    # Step 1+2: Generate PDF
    if not generate_pdf(args.cv, args.out):
        print(json.dumps({"ok": False, "error": "PDF generation failed"}))
        sys.exit(2)

    # Step 3: Read back
    pdf_text = read_pdf_text(args.out)
    pages = get_page_count(args.out)

    # Step 4a: Page count check
    page_ok = (1 <= pages <= 2)
    page_warning = None if page_ok else f"PDF is {pages} pages (expected 1-2)"

    # Step 4b: ATS check
    ats = check_ats(pdf_text, jd_text)

    ats_ok = ats.get("score") is None or ats["score"] >= 50
    ats_warning = None
    if ats.get("score") is not None and ats["score"] < 50:
        ats_warning = (
            f"ATS coverage {ats['score']}% (target ≥55%). "
            f"Consider naturally incorporating: {', '.join(ats['missing_top15'][:8])}"
        )

    result = {
        "ok": page_ok and ats_ok,
        "pdf": args.out,
        "pages": pages,
        "page_ok": page_ok,
        "page_warning": page_warning,
        "ats": ats,
        "ats_ok": ats_ok,
        "ats_warning": ats_warning,
        "pdf_text_chars": len(pdf_text),
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    sys.exit(0 if (page_ok and ats_ok) else 1)


if __name__ == '__main__':
    main()
