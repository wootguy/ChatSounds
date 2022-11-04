
void play_mic_sound(EHandle h_speaker, array<EHandle>@ h_listeners, ChatSound@ sound, int pitch) {	
	CBasePlayer@ speaker = cast<CBasePlayer@>(h_speaker.GetEntity());
	int eidx = speaker.entindex();
	string steamId = g_EngineFuncs.GetPlayerAuthId( speaker.edict() );
	
	if (g_pause_mic_audio) {
		g_PlayerFuncs.ClientPrint(speaker, HUD_PRINTNOTIFY, "[ChatSounds] Mic audio is currently paused.");
		return;
	}
	
	uint32 listeners = 0;
	
	for (uint i = 0; i < h_listeners.size(); i++) {
		CBaseEntity@ ent = h_listeners[i];
		
		if (ent !is null) {
			listeners |= 1 << (ent.entindex() & 31);
		}
	}

	g_EngineFuncs.ServerCommand("play_mic_sound \"" + sound.fpath + "\" " + pitch + " " + CSMIC_VOLUME + " " + eidx + " " + listeners + "\n");
	g_EngineFuncs.ServerExecute();
}

void stop_mic_sound(EHandle h_speaker) {
	CBasePlayer@ speaker = cast<CBasePlayer@>(h_speaker.GetEntity());
	int eidx = speaker.entindex();
	
	g_EngineFuncs.ServerCommand("stop_mic_sound " + eidx + " 1\n");
	g_EngineFuncs.ServerExecute();
}
