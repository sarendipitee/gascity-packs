// Package beadsdoltlite embeds the DoltLite beads provider pack.
package beadsdoltlite

import "embed"

// PackFS contains the DoltLite beads provider pack files.
//
//go:embed pack.toml all:assets doctor commands examples formulas orders skills template-fragments
var PackFS embed.FS
