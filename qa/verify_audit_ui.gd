extends SceneTree
var failures:=0
var checks:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1
 print("PASS: " if ok else "FAIL: ",label)
func _initialize():call_deferred("run")
func run():
 var game=load("res://courtyard.tscn").instantiate()
 game.music_settings_path="user://qa-audio-"+str(Time.get_ticks_usec())+".cfg"
 game.service_url=OS.get_environment("RELAY_TEST_URL")
 root.add_child(game);await process_frame
 game.set_physics_process(false);game.replay.stop();game._reset();game.mode="jev";game.time=20
 var a:Dictionary=game.guards[0]
 game._request_decision(a,"noise",Vector2(-10,0),["inspect"])
 var deadline=Time.get_ticks_msec()+3000
 while game.pending and Time.get_ticks_msec()<deadline:await process_frame
 check(not game.pending and game.trace.size()==2,"same-choice HTTP reply completes after baseline")
 if not game.trace.is_empty():
  var entry:Dictionary=game.trace.back()
  check(entry.get("source")=="Jev" and not entry.get("changed",true),"Jev reply agrees with baseline")
  check(not entry.get("assignments",[]).is_empty(),"continuing assignments are saved with response")
  game._update_ui()
  check(not game.log_label.text.contains("まだ割り当て"),"same-choice response keeps assignment panel populated")
  game.explanation.show_panel(game)
  check(not game.explanation.assignments_label.text.contains("未記録"),"F1 also shows continuing assignments")
  game.explanation.close(game)
 game.replay.scenario="rush";game.active=true;game._update_ui()
 check(game.comparison_label.text.contains(game.replay.condition_label()) and not game.comparison_label.text.contains("銃声9秒"),"selected route survives UI refresh")
 game.replay.playing=true;game.replay.invulnerable=false;game._update_ui()
 check(not game.comparison_label.text.contains("被弾無効"),"new playback label uses ordinary health")
 check(game.music_player.playing and game.music_player.stream.loop,"BGM is playing and loops")
 var master_muted=AudioServer.is_bus_mute(AudioServer.get_bus_index("Master"))
 game._toggle_music()
 check(game.music_muted and AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")),"BGM mute works")
 check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master"))==master_muted,"BGM mute preserves sound effects")
 var settings=ConfigFile.new()
 check(settings.load(game.music_settings_path)==OK and settings.get_value("music","muted",false),"BGM preference saved")
 game._toggle_music()
 check(not game.music_muted and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")),"BGM can be restored")
 DirAccess.remove_absolute(ProjectSettings.globalize_path(game.music_settings_path))
 game.replay.stop();game.queue_free();await process_frame;await create_timer(.2).timeout
 print("AUDIT_UI_CHECKS ",checks," failures ",failures)
 quit(1 if failures else 0)
