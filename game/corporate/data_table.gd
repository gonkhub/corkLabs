# Reads the plain-text data tables (catalog.txt, packages.txt, hq_lines.txt):
# one row per line, columns separated by |, lines starting with # ignored.
# The last column may itself contain | characters.
class_name DataTable
extends RefCounted


## Rows as dictionaries keyed by `columns`. Missing trailing columns are "".
static func read(path: String, columns: PackedStringArray) -> Array[Dictionary]:
	return parse(FileAccess.get_file_as_string(path), columns)


static func parse(text: String, columns: PackedStringArray) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts := line.split("|")
		var row := {}
		for i in columns.size():
			if i == columns.size() - 1:
				row[columns[i]] = "|".join(parts.slice(i)).strip_edges() if i < parts.size() else ""
			else:
				row[columns[i]] = parts[i].strip_edges() if i < parts.size() else ""
		rows.append(row)
	return rows
