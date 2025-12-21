#!/bin/bash
cd "$(dirname "$0")"
swift build -c release 2>/dev/null
exec .build/release/AppleDocsTool
