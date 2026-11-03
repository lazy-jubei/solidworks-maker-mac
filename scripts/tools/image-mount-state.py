#!/usr/bin/env python3
"""Read-only validation of a configured hdiutil image and mount-point pair."""
import os
import plistlib
import subprocess
import sys


def mount_state(images, image, volume, exists=os.path.lexists):
    if not isinstance(images, list):
        raise ValueError('Invalid disk-image inventory')
    image, volume = os.path.realpath(image), os.path.realpath(volume)
    attached = False
    mounted = False
    for item in images:
        backing = item.get('image-path')
        same_image = bool(backing) and os.path.realpath(backing) == image
        attached |= same_image
        for entity in item.get('system-entities', []):
            point = entity.get('mount-point')
            if point and os.path.realpath(point) == volume:
                if not same_image:
                    raise ValueError('Requested mount point belongs to a different disk image')
                mounted = True
    if mounted:
        return 'mounted'
    if attached:
        raise ValueError('Configured disk image is already attached at another location')
    if exists(volume):
        raise ValueError('Requested mount point exists but is not a mount of the configured disk image')
    return 'unmounted'


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: image-mount-state.py <disk image> <mount point>')
    try:
        inventory = plistlib.loads(subprocess.check_output(['hdiutil', 'info', '-plist']))
        print(mount_state(inventory.get('images'), sys.argv[1], sys.argv[2]))
    except (OSError, ValueError, TypeError, AttributeError, subprocess.CalledProcessError) as exc:
        raise SystemExit(f'Storage check failed: {exc}')
