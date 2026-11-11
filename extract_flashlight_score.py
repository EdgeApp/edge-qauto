import subprocess
import os
from playwright.sync_api import sync_playwright
from http.server import SimpleHTTPRequestHandler
from socketserver import TCPServer
import threading
import sys
import re


def run_flashlight(json_path):
    result = subprocess.run(
        ["flashlight", "report", json_path],
        capture_output=True, text=True, check=True
    )
    # Extract the path from the output using regex
    # Look for a line like: 'Opening report: /path/to/file.html'
    match = re.search(r'Opening report: (/.+\.html)', result.stdout)
    if match:
        html_path = match.group(1)
        return html_path
    else:
        # Fallback: try to find any .html path in the output
        match = re.search(r'(/[^\s]+\.html)', result.stdout)
        if match:
            return match.group(1)
        raise RuntimeError(f"Could not find HTML report path in output: {result.stdout}")


def serve_directory(directory, port=8000):
    os.chdir(directory)
    handler = SimpleHTTPRequestHandler
    httpd = TCPServer(("", port), handler)
    thread = threading.Thread(target=httpd.serve_forever)
    thread.daemon = True
    thread.start()
    return httpd


def extract_score_from_html(html_path, port=8000):
    file_name = os.path.basename(html_path)
    url = f"http://localhost:{port}/{file_name}"

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto(url)
        page.wait_for_selector('text[aria-label="Score"]')
        score = page.locator('text[aria-label="Score"]').text_content()
        browser.close()
    return score


def main():
    if len(sys.argv) < 2:
        print("Usage: python extract_flashlight_score.py <json_file>")
        sys.exit(1)
    json_path = sys.argv[1]
    html_path = run_flashlight(json_path)
    directory = os.path.dirname(html_path) or "."

    httpd = serve_directory(directory, port=8000)
    try:
        score = extract_score_from_html(html_path, port=8000)
        print("Extracted score:", score)
    finally:
        httpd.shutdown()


if __name__ == "__main__":
    main() 