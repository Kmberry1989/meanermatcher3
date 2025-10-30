extends Label

# This script controls the behavior of the score pop-up label.

func _ready():
	# This animation starts as soon as the label is added to the scene.
	var tween = get_tree().create_tween()
	
	# Make the move and fade animations happen at the same time.
	tween.set_parallel(true)
	
	# Animate the label moving upwards by 60 pixels over 0.8 seconds.
	tween.tween_property(self, "position:y", position.y - 60, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	
	# Animate the label fading out completely over the same duration.
	tween.tween_property(self, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	
	# Once the animation is finished, remove the label from the game.
	tween.finished.connect(queue_free)


