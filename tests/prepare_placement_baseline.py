"""Keep the original main implementation available for motion regressions."""
from pathlib import Path
import subprocess

BASE = "7f17c8ce59dbb95bbdb83be1a2ccbdd4d9f43efd"
text = subprocess.check_output(
    ["git", "show", f"{BASE}:scenes/game/gem_flights.gd"], text=True
)
out = Path("build/placement-checks/legacy_gem_flights.gd")
out.parent.mkdir(parents=True, exist_ok=True)
# Isolated reference instances are destroyed between cases. Keep the original
# delays while avoiding the old lambda's freed-node capture on scene teardown.
text = text.replace("class_name GemFlights\n", "", 1)
text = text.replace(
    'get_tree().create_timer(seconds).timeout.connect(func() -> void:\n'
    '\t\tif is_instance_valid(node):\n\t\t\tnode.queue_free())',
    'get_tree().create_timer(seconds).timeout.connect(node.queue_free)',
)
out.write_text(text)
print("Placement reference: current main at", BASE[:7])
