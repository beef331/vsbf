# Package

version       = "0.1.7"
author        = "Jason"
description   = "A new awesome nimble package"
license       = "MIT"

# Dependencies

requires "nim >= 2.2.0"
requires "stew >= 0.2.0"


namedbin = {"vsbf/dumper": "vsbfdumper"}.toTable()
