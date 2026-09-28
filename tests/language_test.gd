extends SceneTree
const Vietnamese = preload("res://scripts/language_translation.gd")
func _initialize():
	var translation = Vietnamese.new()
	TranslationServer.add_translation(translation)
	TranslationServer.set_locale("vi")
	var cases = {
		"Start":"Bắt đầu",
		"ALLOY":"HỢP KIM",
		"Upgrade Barracks to level 2 to train Medic.":"Nâng Doanh trại lên cấp 2 để huấn luyện Quân y.",
		"Need 180 alloy and 90 energy more to build Foundry. Assign Harvesters to deposits.":"Cần thêm 180 hợp kim và 90 năng lượng để xây Nhà máy. Hãy cho Thợ mỏ khai thác.",
		"  Start  ":"  Bắt đầu  ",
		"Q / E / R / T / Y":"Q / E / R / T / Y"
	}
	var failures = 0
	for source in cases:
		if tr(source) != cases[source]:
			printerr("FAIL: ",source," -> ",tr(source)); failures += 1
	TranslationServer.set_locale("en")
	if tr("Start") != "Start": failures += 1
	print("LANGUAGE RESULT: %d failures" % failures)
	TranslationServer.remove_translation(translation)
	quit(1 if failures else 0)
