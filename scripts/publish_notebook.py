from nbconvert import HTMLExporter
import nbformat
import os

def save_notebook_as_html(notebook_path, output_path=None):
    # If output_path is not provided, use the same directory as the notebook
    if output_path is None:
        notebook_dir = os.path.dirname(notebook_path)
        notebook_name = os.path.splitext(os.path.basename(notebook_path))[0]
        output_path = os.path.join(notebook_dir, f"{notebook_name}.html")

    # Load the notebook
    with open(notebook_path, 'r') as f:
        notebook = nbformat.read(f, as_version=4)

    # Configure the HTML exporter
    html_exporter = HTMLExporter()
    html_exporter.template_name = 'full'

    # Convert the notebook to HTML
    (body, resources) = html_exporter.from_notebook_node(notebook)

    # Save the HTML output to a file
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(body)

    print(f"Notebook saved as HTML: {output_path}")
