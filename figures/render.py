"""Render an HTML page to PNG (or a full-page screenshot) with Chromium.

Usage:
  python3 figures/render.py <page.html> <out.png> <width> <height> [scale]    fixed viewport
  python3 figures/render.py --full <page.html> <out.png> <width> [scale]      full-page screenshot

Needs the Python Playwright package with Chromium (pip install playwright; playwright install chromium).
"""
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

args = sys.argv[1:]
full = args and args[0] == "--full"
if full:
    args = args[1:]
    page_path, out, width = args[0], args[1], int(args[2])
    height = 800
    scale = float(args[3]) if len(args) > 3 else 1
else:
    page_path, out, width, height = args[0], args[1], int(args[2]), int(args[3])
    scale = float(args[4]) if len(args) > 4 else 2

with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page(viewport={"width": width, "height": height}, device_scale_factor=scale)
    page.goto(Path(page_path).resolve().as_uri())
    page.wait_for_load_state("networkidle")
    page.evaluate("document.fonts.ready")
    page.screenshot(path=out, full_page=full)
    browser.close()
print("rendered", out)
