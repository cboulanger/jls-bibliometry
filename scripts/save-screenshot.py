import sys
from playwright.sync_api import sync_playwright
from urllib.parse import urljoin
from urllib.request import pathname2url
import os
import time

def save_screenshot(playwright, file_path: str, device_scale_factor=5, delay=2):
    browser = playwright.chromium.launch()
    context = browser.new_context(device_scale_factor=device_scale_factor)
    page = context.new_page()
    file_url = urljoin('file:', pathname2url(os.path.abspath(file_path)))
    page.goto(file_url)
    time.sleep(delay)
    page.evaluate("network.stopSimulation()")

    # wait until animation has been drawn
    #page.evaluate("""
    #window.waitForAfterDrawing = () => {
    #    return new Promise((resolve) => {
    #        network.on('afterDrawing', resolve);
    #    });
    #};
    #""")
    #page.evaluate("window.waitForAfterDrawing()")

    # Set the viewport to cover the entire page content
    dimensions = page.evaluate('''() => {
        return {
            width: document.documentElement.scrollWidth,
            height: document.documentElement.scrollHeight,
            deviceScaleFactor: window.devicePixelRatio,
        }
    }''')
    page.set_viewport_size({
        'width': dimensions['width'],
        'height': dimensions['height'],
    })

    # Take a screenshot of the entire page
    img_filename = file_path.replace(".html", ".png")
    page.screenshot(path=img_filename, full_page=True, scale="device")

    # Close the browser
    browser.close()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python script_name.py <path_to_html_file>")
        sys.exit(1)

    file_path = sys.argv[1]
    delay = int(sys.argv[2]) if len(sys.argv) > 2 else None
    with sync_playwright() as p:
        save_screenshot(p, file_path, delay=delay)