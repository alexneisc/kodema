import Foundation

// ANSI colors
let localColor = "\u{001B}[32m"
let cloudColor = "\u{001B}[33;1m"
let errorColor = "\u{001B}[31;1m"
let resetColor = "\u{001B}[0m"
let boldColor = "\u{001B}[1m"
let dimColor = "\u{001B}[2m"

// B2 limits: file name can be up to 1000 bytes (UTF-8)
// Use 950 to leave some safety margin for encoding
let maxB2PathLength = 950
