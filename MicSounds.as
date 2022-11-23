
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

void update_mic_sounds_config(CBasePlayer@ plr) {	
	if (plr is null or !plr.IsConnected()) {
		return;
	}
	
	PlayerState@ state = getPlayerState(plr);
		
	bool isGlobal = state.micMode == MICMODE_GLOBAL || state.micMode == MICMODE_SUPER_GLOBAL;
	g_EngineFuncs.ServerCommand("config_mic_sound " + plr.entindex() + " " + state.reliablePackets + " " + isGlobal + " " + state.volume + "\n");

	g_EngineFuncs.ServerExecute();
}

void update_mic_sounds_config_all() {	
	for (int i = 1; i <= g_Engine.maxClients; i++) {
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		PlayerState@ state = getPlayerState(plr);
		if (g_EngineFuncs.Time() - state.joinTime < CSRELIABLE_DELAY-1) {
			continue; // don't enable yet. A separate config is coming later
		}
		
		bool isGlobal = state.micMode == MICMODE_GLOBAL || state.micMode == MICMODE_SUPER_GLOBAL;
		g_EngineFuncs.ServerCommand("config_mic_sound " + i + " " + state.reliablePackets + " " + isGlobal + " " + state.volume + "\n");
	}

	g_EngineFuncs.ServerExecute();
}

void stop_mic_sound(EHandle h_speaker) {
	CBasePlayer@ speaker = cast<CBasePlayer@>(h_speaker.GetEntity());
	int eidx = speaker.entindex();
	
	g_EngineFuncs.ServerCommand("stop_mic_sound " + eidx + " 1\n");
	g_EngineFuncs.ServerExecute();
}
