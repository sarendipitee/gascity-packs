// Package jjw embeds the jjw workspace helper pack.
package jjw

import "embed"

// PackFS contains the jjw workspace helper pack files.
//
//go:embed pack.toml README.md doctor commands formulas orders all:assets
var PackFS embed.FS
