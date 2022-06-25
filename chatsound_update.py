import os, subprocess, shlex, time

sven_root_path = 'C:\\Games\\Steam\\steamapps\\common\\Sven Co-op'

sound_root_path = os.path.join(sven_root_path, "svencoop_downloads\\sound")

sound_search_paths = [
	os.path.join(sven_root_path, "svencoop_addon/sound"),
	os.path.join(sven_root_path, "svencoop_downloads/sound"),
	os.path.join(sven_root_path, "svencoop/sound"),
]

chatsound_cfg_path = os.path.join(sven_root_path, 'svencoop_addon\\scripts\\plugins\\cfg\\ChatSounds.txt')
steam_voice_path = os.path.join(sven_root_path, 'svencoop_addon\\scripts\\plugins\\radio\\lib\\steam_voice.exe')

steamId = 0 # must be unique per sound or else multiple mic streams will conflict each other if played at the same time

with open(chatsound_cfg_path) as file:
	for line in file:
		parts = line.split()
		if len(parts) < 2 or "[extra_sounds]" in line or line[0] == '/':
			continue
		
		sound_path = None
		for search_path in sound_search_paths:
			sound_path = os.path.join(search_path, parts[1])
			if os.path.exists(sound_path):
				break
			
		spk_path = sound_path.replace(".wav", ".spk")
		
		#if os.path.exists(spk_path):
		#	continue
		
		print(spk_path)
		cmd = '"%s" "%s" "%s" %s' % (steam_voice_path, sound_path, spk_path, steamId)
		steamId += 1
		print(cmd)
		#os.system(cmd)
		#subprocess.run(shlex.split(cmd))
		
		child = subprocess.Popen(shlex.split(cmd), stdout=subprocess.PIPE)
		returnCode = child.wait()
		
		if returnCode:
			print("\n\nFailed to update chatsounds %s on %s" % (returnCode, parts[1]))
			break