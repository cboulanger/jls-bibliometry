import os
from jinja2 import Environment, FileSystemLoader

# create index.html for the "docs" directory, which will be published as the github pages of this project
def generate_html(directory):
    # Verify the directory exists
    if not os.path.isdir(directory):
        print(f"Directory {directory} does not exist.")
        return

    # Get list of files
    files = os.listdir(directory)
    files = [f for f in files if not f.startswith('.')]  # Ignore hidden files

    # Create Jinja2 environment and load the template
    env = Environment(loader=FileSystemLoader('.'))
    template = env.get_template('lib/index.html.tmpl')

    # Render the template with the list of files
    html_content = template.render(directory=directory, files=files)

    # Write the rendered HTML to a file
    with open(os.path.join(directory, 'index.html'), 'w') as html_file:
        html_file.write(html_content)

generate_html('docs')
