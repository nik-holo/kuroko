#!/usr/bin/env swift
// Sets a Finder custom icon on a file, folder, or mounted volume.
// Usage: swift scripts/seticon.swift <icon.icns> <target>

import AppKit

guard CommandLine.arguments.count == 3,
      let icon = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: seticon.swift <icon.icns> <target>\n".utf8))
    exit(2)
}
let target = CommandLine.arguments[2]
let ok = NSWorkspace.shared.setIcon(icon, forFile: target, options: [])
print(ok ? "icon set on \(target)" : "failed to set icon on \(target)")
exit(ok ? 0 : 1)
