# Package

version       = "0.1.2"
author        = "Jason"
description   = "A new awesome nimble package"
license       = "MIT"

# Dependencies

requires "nim >= 2.2.0"


namedbin = {"vsbf/dumper": "vsbfdumper"}.toTable()
