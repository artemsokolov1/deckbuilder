extends SceneTree
## Прогон интерфейса без окна: бот проходит серии во всех режимах через обработчики сцен,
## проверяет обучение, выход по Esc во время анимации, повторные нажатия и повтор seed.
## Запуск: godot --headless --path . -s tests/smoke.gd
## Сама логика — в smoke_runner.gd: она ссылается на автозагрузку Game,
## поэтому загружается уже после её регистрации.


var runner  # держим ссылку, иначе корутина прогона исчезнет вместе с объектом


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	runner = load("res://tests/smoke_runner.gd").new()
	runner.run(self)
