from pathlib import Path
import json
import shutil

from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import A3
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader


OUT = Path(__file__).parent
SOURCE = Path('/Users/dylanxu/.codex/generated_images/01a14228-7e62-7a63-9765-390c98ca4bb9/exec-dee16acc-fa16-4965-af80-257c0d06dadb.png')
ART = OUT / 'artwork.png'
PDF = OUT / 'FTC-Event-Scout-Early-AI-A3-v2.pdf'
shutil.copy2(SOURCE, ART)

pdfmetrics.registerFont(TTFont('PosterTitle', '/System/Library/Fonts/Supplemental/Impact.ttf'))
pdfmetrics.registerFont(TTFont('PosterBody', '/System/Library/Fonts/Supplemental/Arial.ttf'))
pdfmetrics.registerFont(TTFont('PosterBold', '/System/Library/Fonts/Supplemental/Arial Bold.ttf'))

W, H = A3
MARGIN = 44
INK = HexColor('#F3EEE2')
BODY = HexColor('#D0CFDC')
ACCENTS = [HexColor('#FF8B65'), HexColor('#7BDEF0'), HexColor('#C6A0F6')]
SECTIONS = [
    ('PROBLEM DEFINITION', 'FTC scouts need to compare many teams and understand the matches behind the rankings. One rank cannot show autonomous strengths, alliance context or abnormal scores. The project brings event data and observations together to support informed scouting decisions.'),
    ('SUCCESS CRITERIA', 'Load teams and scored matches for an event.\nSort rankings and compare available OPR metrics.\nOpen charts, team histories and score breakdowns.\nShow predictions with data-quality labels.\nSave and reload color-coded local scouting tags.'),
    ('PROBLEM SCENARIO', 'At an FTC event, a scout selects a season and event code, compares teams and investigates match evidence.\n\nLanguages & apps: Swift / SwiftUI for macOS; a local Python 3 helper; FIRST Events data processed into CSV. FTCScout supplies pre-event history.\n\nMethods & algorithms: least-squares OPR (Offensive Power Rating), with one-sided Jacobi SVD in the Swift prediction layer. OPRc filters alliance residuals once using 1.5 x IQR (interquartile range), then recalculates OPR. Match estimates sum team OPRc values.'),
    ('THE SOLUTION', 'FTC Event Scout combines sortable rankings, OPR charts, event highlights, team histories and detailed score breakdowns in one native app.\n\nScouts compare Auto, Teleop, Endgame and overall contribution; inspect the alliances behind a score; and save reusable, color-coded team tags locally.\n\nThe Predictions view estimates red and blue alliance scores, winner and signed margin for scheduled or custom four-team matchups.'),
    ('IMPORTANT CONSIDERATIONS', 'OPR and OPRc are scouting estimates. Defense, alliance interaction and robot failures can change outcomes. Predictions flag limited data; missing team estimates make a prediction unavailable.'),
]


def wrapped_lines(text, font, size, width):
    lines, line = [], ''
    for word in text.split():
        candidate = f'{line} {word}'.strip()
        if pdfmetrics.stringWidth(candidate, font, size) > width:
            lines.append(line)
            line = word
        else:
            line = candidate
    if line:
        lines.append(line)
    return lines


c = canvas.Canvas(str(PDF), pagesize=A3, pageCompression=1)
c.setTitle('FTC Event Scout - Early AI A3 Poster')
c.setAuthor('FTC Event Scout')
c.setSubject('Problem definition, success criteria, technical scenario, solution and limitations')
c.setFillColor(HexColor('#0B0618'))
c.rect(0, 0, W, H, fill=1, stroke=0)
c.drawImage(ImageReader(str(ART)), 0, 130, width=W, height=H)

# Dark panels preserve legibility while the central robot remains visible.
c.saveState()
c.setFillColor(HexColor('#0B0618'))
c.setFillAlpha(0.97)
c.rect(0, 1024, W, H - 1024, fill=1, stroke=0)
c.rect(0, 0, W, 420, fill=1, stroke=0)
c.setFillAlpha(0.91)
c.rect(0, 796, W, 228, fill=1, stroke=0)
c.restoreState()

title = 'FTC EVENT SCOUT'
title_size = 100
title_width = pdfmetrics.stringWidth(title, 'PosterTitle', title_size)
title_x = (W - title_width) / 2
title_y = H - 114
c.setFont('PosterTitle', title_size)
for dx, color in [(-1.05, '#CB477B'), (1.05, '#4CBCCC'), (0, '#F3EEE2')]:
    c.setFillColor(HexColor(color))
    c.drawString(title_x + dx, title_y, title)
c.setFont('PosterBody', 17)
c.setFillColor(INK)
c.drawCentredString(W / 2, H - 151, 'Native macOS scouting for FIRST Tech Challenge')

gap = 32
col_width = (W - 2 * MARGIN - gap) / 2
line_counts = []


def section_heading(index, x, y, width):
    heading = SECTIONS[index][0]
    c.setFillColor(ACCENTS[index % len(ACCENTS)])
    c.setFont('PosterBold', 10)
    c.drawString(x, y + 25, f'0{index + 1}')
    c.setStrokeColor(ACCENTS[index % len(ACCENTS)])
    c.setLineWidth(0.7)
    c.line(x + 27, y + 28, x + width, y + 28)
    c.setFillColor(INK)
    c.setFont('PosterBold', 17)
    assert pdfmetrics.stringWidth(heading, 'PosterBold', 17) <= width
    c.drawString(x, y, heading)


def paragraph(text, x, y, width, size=12.8, leading=18, floor=0):
    c.setFillColor(BODY)
    c.setFont('PosterBody', size)
    count = 0
    for block in text.split('\n\n'):
        for line in wrapped_lines(block, 'PosterBody', size, width):
            assert y >= floor, (line, y, floor)
            c.drawString(x, y, line)
            y -= leading
            count += 1
        y -= 7
    line_counts.append(count)
    return y


section_heading(0, MARGIN, 976, col_width)
paragraph(SECTIONS[0][1], MARGIN, 949, col_width, floor=812)

right = MARGIN + col_width + gap
section_heading(1, right, 976, col_width)
c.setFont('PosterBody', 11)
c.setFillColor(BODY)
c.drawString(right, 951, 'Observable project targets - the scout can:')
y = 925
criterion_lines = 0
for criterion in SECTIONS[1][1].split('\n'):
    c.setFillColor(ACCENTS[1])
    c.circle(right + 2, y + 4, 1.5, fill=1, stroke=0)
    c.setFillColor(BODY)
    c.setFont('PosterBody', 12.2)
    for line in wrapped_lines(criterion, 'PosterBody', 12.2, col_width - 14):
        assert y >= 812
        c.drawString(right + 14, y, line)
        y -= 16.5
        criterion_lines += 1
    y -= 8
line_counts.append(criterion_lines)

section_heading(2, MARGIN, 379, col_width)
paragraph(SECTIONS[2][1], MARGIN, 352, col_width, size=12.2, leading=17, floor=123)
section_heading(3, right, 379, col_width)
paragraph(SECTIONS[3][1], right, 352, col_width, size=12.2, leading=17, floor=123)

c.setStrokeColor(HexColor('#50415E'))
c.line(MARGIN, 111, W - MARGIN, 111)
c.setFillColor(INK)
c.setFont('PosterBold', 11)
c.drawString(MARGIN, 92, SECTIONS[4][0])
paragraph(SECTIONS[4][1], MARGIN, 75, W - 2 * MARGIN, size=10.5, leading=14, floor=45)

c.setFillColor(HexColor('#9793AA'))
c.setFont('PosterBody', 9)
c.drawString(MARGIN, 24, 'macOS 14+  |  Python 3  |  FIRST Events API credentials')
c.drawRightString(W - MARGIN, 24, 'github.com/Sakzyo/FTC_Event_Scout')
c.showPage()
c.save()

(OUT / 'manifest-v2.json').write_text(json.dumps({
    'title': 'FTC Event Scout - Early AI A3 Poster',
    'dimensions_mm': [297, 420],
    'orientation': 'portrait',
    'page_count': 1,
    'generation': 'Built-in ImageGen; one background generation and one style refinement',
    'source_artwork_pixels': [1054, 1492],
    'typography': 'Vector text in the PDF; embedded Impact and Arial fonts',
    'content_source': 'Project README.md and matching Swift source, reviewed locally',
    'sections': [{'heading': h, 'text': t} for h, t in SECTIONS],
    'paragraph_line_counts': line_counts,
    'pdf': PDF.name,
    'png': 'FTC-Event-Scout-Early-AI-A3-v2.png',
    'raster_export_dpi': 300,
    'note': '300 dpi describes the raster export grid; generated artwork retains its native detail. No bleed added.'
}, indent=2) + '\n')
print(PDF)
