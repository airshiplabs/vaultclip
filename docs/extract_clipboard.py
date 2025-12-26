#!/usr/bin/env python3
"""
Extract clipboard contents from Clipy data files.
Clipy stores clipboard history as binary plist files with NSKeyedArchiver format.
"""

import plistlib
import glob
import os
import sys
from datetime import datetime
from pathlib import Path


def extract_clipboard_text(filepath):
    """
    Extract the clipboard text from a Clipy .data file.

    Args:
        filepath: Path to the .data file

    Returns:
        The clipboard text string, or None if not found
    """
    try:
        with open(filepath, 'rb') as f:
            data = plistlib.load(f)

        # NSKeyedArchiver stores objects in an array
        objects = data.get('$objects', [])
        if len(objects) < 2:
            return None

        # The main object is typically at index 1
        main_obj = objects[1]
        if not isinstance(main_obj, dict):
            return None

        # Get the UID reference for stringValue
        string_value_uid = main_obj.get('stringValue')
        if not string_value_uid:
            return None

        # UID is a special type - get its integer value
        # In plistlib, UIDs have a 'data' attribute
        if hasattr(string_value_uid, 'data'):
            uid_index = string_value_uid.data
        else:
            uid_index = int(string_value_uid)

        # Get the actual string from the objects array
        if uid_index < len(objects):
            clipboard_text = objects[uid_index]
            if isinstance(clipboard_text, str):
                return clipboard_text

        return None

    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return None


def get_file_timestamp(filepath):
    """Get the modification time of a file."""
    return os.path.getmtime(filepath)


def main():
    # Default Clipy directory on macOS
    default_clipy_dir = "~/Library/Application Support/Clipy"

    # Allow user to specify a custom directory via command line argument
    if len(sys.argv) > 1:
        clipy_dir = Path(sys.argv[1]).expanduser()
    else:
        clipy_dir = Path(default_clipy_dir).expanduser()

    # Check if directory exists
    if not clipy_dir.exists():
        print(f"Error: Directory not found: {clipy_dir}")
        print(f"\nUsage: {sys.argv[0]} [clipy_directory]")
        print(f"Default directory: {default_clipy_dir}")
        return

    if not clipy_dir.is_dir():
        print(f"Error: {clipy_dir} is not a directory")
        return

    # Get all .data files in the Clipy directory
    data_files = glob.glob(str(clipy_dir / '*.data'))

    if not data_files:
        print(f"No .data files found in {clipy_dir}")
        return

    print(f"Reading clipboard history from: {clipy_dir}")
    print(f"Found {len(data_files)} clipboard history files.\n")
    print("=" * 80)

    # Sort files by modification time (newest first)
    data_files.sort(key=get_file_timestamp, reverse=True)

    for i, filepath in enumerate(data_files, 1):
        filename = os.path.basename(filepath)
        mod_time = datetime.fromtimestamp(get_file_timestamp(filepath))

        clipboard_text = extract_clipboard_text(filepath)

        if clipboard_text:
            # Truncate long texts for display
            display_text = clipboard_text
            if len(display_text) > 200:
                display_text = display_text[:200] + "..."

            print(f"\n[{i}] {filename}")
            print(f"    Modified: {mod_time.strftime('%Y-%m-%d %H:%M:%S')}")
            print(f"    Length: {len(clipboard_text)} characters")
            print(f"    Content: {display_text}")
        else:
            print(f"\n[{i}] {filename}")
            print(f"    Modified: {mod_time.strftime('%Y-%m-%d %H:%M:%S')}")
            print(f"    Content: (Could not extract text)")

        print("-" * 80)


if __name__ == "__main__":
    main()
