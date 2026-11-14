class_name ExplainButton
extends Button
## STUB owned by worker B. A small "?" button next to a reading; pressing it shows the plain-language explanation
## for `explanation_id` and offers its sources.

var explanation_id := ""


static func make(id: String) -> ExplainButton:
	var b := ExplainButton.new()
	b.explanation_id = id
	b.text = "?"
	return b
