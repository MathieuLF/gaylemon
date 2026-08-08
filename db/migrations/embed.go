package migrations

import "embed"

// Files contient les migrations SQL versionnées intégrées au binaire web.
//
//go:embed *.sql
var Files embed.FS
