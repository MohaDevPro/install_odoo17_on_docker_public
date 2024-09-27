import subprocess
import sys

def get_installed_packages():
    # Get the list of installed packages
    result = subprocess.run(['pip3', 'list', '--format=freeze'], stdout=subprocess.PIPE, text=True)
    installed_packages = {line.split('==')[0] for line in result.stdout.splitlines()}
    return installed_packages

def get_requirements():
    # Read the requirements.txt file
    with open('/etc/odoo/requirements.txt', 'r') as f:
        requirements = {line.strip().split('==')[0] for line in f if line.strip() and not line.startswith('#')}
    return requirements

def install_missing_packages(requirements, installed):
    print("install_missing_packages: \n")
    # Install missing packages
    missing_packages = requirements - installed
    if missing_packages:
        for package in missing_packages:
            print(f"Attempting to install package: {package}")
            try:
                subprocess.run(['pip3', 'install', package], check=True)
                print(f"Successfully installed package: {package}")
            except subprocess.CalledProcessError:
                print(f"Failed to install package: {package}, skipping.")
    else:
        print("No missing packages")


if __name__ == "__main__":
    print(f"__main__  \n")
    installed_packages = get_installed_packages()
    requirements = get_requirements()
    install_missing_packages(requirements, installed_packages)
