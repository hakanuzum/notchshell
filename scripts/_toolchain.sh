#!/bin/bash
# Ensure a full Xcode toolchain is selected. Meant to be sourced, not executed.
#
# Swift macro plugins (KeyboardShortcuts' #Preview) cannot be built with
# CommandLineTools alone; the build fails with:
#   external macro implementation type 'PreviewsMacros.SwiftUIView' could not be found
# When xcode-select points at CommandLineTools, fall back to an installed Xcode.

if [ -z "${DEVELOPER_DIR:-}" ]; then
    case "$(xcode-select -p 2>/dev/null)" in
        *Xcode*)
            : # a full Xcode is already selected
            ;;
        *)
            for _xc in /Applications/Xcode.app /Applications/Xcode-*.app; do
                if [ -d "$_xc/Contents/Developer" ]; then
                    export DEVELOPER_DIR="$_xc/Contents/Developer"
                    echo "==> Using DEVELOPER_DIR=$DEVELOPER_DIR"
                    break
                fi
            done
            unset _xc
            ;;
    esac
fi

if [ -z "${DEVELOPER_DIR:-}" ] && ! xcode-select -p 2>/dev/null | grep -q Xcode; then
    echo "WARNING: no full Xcode toolchain found — Swift macro plugins will fail to build." >&2
    echo "         Install Xcode, or run: sudo xcode-select -s /Applications/Xcode.app" >&2
fi
