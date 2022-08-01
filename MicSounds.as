float g_packet_delay = 0.05f;
array<CScheduledFunction@> g_mic_timers(33);

class VoicePacket {
	uint size = 0;
	
	array<string> sdata;
	array<uint32> ldata;
	array<uint8> data;
	
	void send(CBasePlayer@ speaker, CBasePlayer@ listener) {
		bool send_reliable_packets = getPlayerState(listener).reliablePackets;
	
		NetworkMessageDest sendMode = send_reliable_packets ? MSG_ONE : MSG_ONE_UNRELIABLE;
		
		/*
		if (state.reliablePackets) {
			sendMode = MSG_ONE;
			
			if (state.reliablePacketsStart > g_EngineFuncs.Time()) {
				sendMode = MSG_ONE_UNRELIABLE;
			} else if (!state.startedReliablePackets) {
				state.startedReliablePackets = true;
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTNOTIFY, "[Radio] Reliable packets started.\n");
			}
		}
		*/
		
		// svc_voicedata
		NetworkMessage m(sendMode, NetworkMessages::NetworkMessageType(53), listener.edict());
			m.WriteByte(speaker.entindex()-1); // entity which is "speaking"
			m.WriteShort(size); // compressed audio length
			
			// Ideally, packet data would be written once and re-sent to whoever wants it.
			// However there's no way to change the message destination after creation.
			// Data is combined into as few chunks as possible to minimize the loops
			// needed to write the data. An empty for-loop with thousands of iterations
			// can kill server performance so this is very important. This optimization
			// loops about 10% as much as writing bytes one-by-one for every player.

			// First, data is split into strings delimted by zeros. It can't all be one string
			// because a string can't contain zeros, and the data is not guaranteed to end with a 0.
			for (uint k = 0; k < sdata.size(); k++) {
				m.WriteString(sdata[k]); // includes the null terminater
			}
			
			// ...but that can leave a large chunk of bytes at the end, so the remainder is
			// also combined into 32bit ints.
			for (uint k = 0; k < ldata.size(); k++) {
				m.WriteLong(ldata[k]);
			}
			
			// whatever is left at this point will be less than 4 iterations.
			for (uint k = 0; k < data.size(); k++) {
				m.WriteByte(data[k]);
			}
			
		m.End();
	}
}

// convert lowercase hex letter to integer
array<uint8> char_to_nibble = {
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 1, 2, 3, 4, 5, 6, 7,
	8, 9, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 10, 11, 12, 13, 14, 15
};

// can't append uint8 to strings directly (even with char cast), so using this lookup table instead
array<char> HEX_CODES = {
	'\x00','\x01','\x02','\x03','\x04','\x05','\x06','\x07','\x08','\x09','\x0A','\x0B','\x0C','\x0D','\x0E','\x0F',
	'\x10','\x11','\x12','\x13','\x14','\x15','\x16','\x17','\x18','\x19','\x1A','\x1B','\x1C','\x1D','\x1E','\x1F',
	'\x20','\x21','\x22','\x23','\x24','\x25','\x26','\x27','\x28','\x29','\x2A','\x2B','\x2C','\x2D','\x2E','\x2F',
	'\x30','\x31','\x32','\x33','\x34','\x35','\x36','\x37','\x38','\x39','\x3A','\x3B','\x3C','\x3D','\x3E','\x3F',
	'\x40','\x41','\x42','\x43','\x44','\x45','\x46','\x47','\x48','\x49','\x4A','\x4B','\x4C','\x4D','\x4E','\x4F',
	'\x50','\x51','\x52','\x53','\x54','\x55','\x56','\x57','\x58','\x59','\x5A','\x5B','\x5C','\x5D','\x5E','\x5F',
	'\x60','\x61','\x62','\x63','\x64','\x65','\x66','\x67','\x68','\x69','\x6A','\x6B','\x6C','\x6D','\x6E','\x6F',
	'\x70','\x71','\x72','\x73','\x74','\x75','\x76','\x77','\x78','\x79','\x7A','\x7B','\x7C','\x7D','\x7E','\x7F',
	'\x80','\x81','\x82','\x83','\x84','\x85','\x86','\x87','\x88','\x89','\x8A','\x8B','\x8C','\x8D','\x8E','\x8F',
	'\x90','\x91','\x92','\x93','\x94','\x95','\x96','\x97','\x98','\x99','\x9A','\x9B','\x9C','\x9D','\x9E','\x9F',
	'\xA0','\xA1','\xA2','\xA3','\xA4','\xA5','\xA6','\xA7','\xA8','\xA9','\xAA','\xAB','\xAC','\xAD','\xAE','\xAF',
	'\xB0','\xB1','\xB2','\xB3','\xB4','\xB5','\xB6','\xB7','\xB8','\xB9','\xBA','\xBB','\xBC','\xBD','\xBE','\xBF',
	'\xC0','\xC1','\xC2','\xC3','\xC4','\xC5','\xC6','\xC7','\xC8','\xC9','\xCA','\xCB','\xCC','\xCD','\xCE','\xCF',
	'\xD0','\xD1','\xD2','\xD3','\xD4','\xD5','\xD6','\xD7','\xD8','\xD9','\xDA','\xDB','\xDC','\xDD','\xDE','\xDF',
	'\xE0','\xE1','\xE2','\xE3','\xE4','\xE5','\xE6','\xE7','\xE8','\xE9','\xEA','\xEB','\xEC','\xED','\xEE','\xEF',
	'\xF0','\xF1','\xF2','\xF3','\xF4','\xF5','\xF6','\xF7','\xF8','\xF9','\xFA','\xFB','\xFC','\xFD','\xFE','\xFF'
};

File@ openMicSoundfile(string fpath) {
	File@ file = @g_FileSystem.OpenFile(fpath, OpenFile::READ);	
	
	if (file is null or !file.IsOpen()) {
		println("[ChatSounds] Mic sound file not found: " + fpath + "\n");
		g_Log.PrintF("[ChatSounds] Mic sound file not found: " + fpath + "\n");
	}
	
	return file;
}

// returns a list of packets to be sent in delayed NetworkMessages
array<VoicePacket> load_mic_sound(string fpath) {
	array<VoicePacket> packets; 
	
	File@ file = openMicSoundfile(fpath);
	
	if (file is null) {
		return packets;
	}
	
	while (!file.EOFReached()) {
		string line;
		file.ReadLine(line);
		
		if (line.IsEmpty()) {
			break;
		}
		
		packets.insertLast(parse_mic_packet(line));
	}
	
	file.Close();
	
	return packets;
}

VoicePacket parse_mic_packet(string line) {
	VoicePacket packet;
		
	string sdat = "";
	
	for (uint i = 0; i < line.Length()-1; i += 2) {
		uint n1 = char_to_nibble[ uint(line[i]) ];
		uint n2 = char_to_nibble[ uint(line[i + 1]) ];
		uint8 bval = (n1 << 4) + n2;
		packet.data.insertLast(bval);
		
		// combine into 32bit ints for faster writing later
		if (packet.data.size() == 4) {
			uint32 val = (packet.data[3] << 24) + (packet.data[2] << 16) + (packet.data[1] << 8) + packet.data[0];
			packet.ldata.insertLast(val);
			packet.data.resize(0);
		}
		
		// combine into string for even faster writing later
		if (bval == 0) {
			packet.sdata.insertLast(sdat);
			packet.ldata.resize(0);
			packet.data.resize(0);
			sdat = "";
		} else {
			sdat += HEX_CODES[bval];
		}
		
		packet.size++;
	}
	
	return packet;
}

void play_mic_sound(EHandle h_speaker, array<EHandle>@ h_listeners, ChatSound@ sound, int pitch) {	
	CBasePlayer@ speaker = cast<CBasePlayer@>(h_speaker.GetEntity());
	int eidx = speaker.entindex();
	
	if (g_pause_mic_audio) {
		g_PlayerFuncs.ClientPrint(speaker, HUD_PRINTNOTIFY, "[ChatSounds] Mic audio is currently paused.");
		return;
	}

	if (g_mic_timers[eidx] !is null) {
		g_Scheduler.RemoveTimer(g_mic_timers[eidx]);
		@g_mic_timers[eidx] = null;
	}

	string spk_file = g_spk_folder + "/" + eidx + ".spk";
	string spk_file_temp = g_spk_folder + "/" + eidx + "_temp.spk";
	
	File@ file = @g_FileSystem.OpenFile(spk_file, OpenFile::WRITE);	
	
	// delete the file and wait for python to recreate it with unique pitch and ID data
	if (file !is null and file.IsOpen()) {
		file.Remove();
	}
	
	send_steam_voice_message(sound.trigger + " " + pitch + " " + eidx);
	wait_mic_sound(h_speaker, h_listeners, spk_file, g_Engine.time);
}

void wait_mic_sound(EHandle h_speaker, array<EHandle>@ h_listeners, string spkPath, float waitTimeStart) {
	CBaseEntity@ speaker = h_speaker;
	
	if (speaker is null) {
		return;
	}
	
	File@ file = @g_FileSystem.OpenFile(spkPath, OpenFile::READ);	
	
	if (file !is null and file.IsOpen()) {
		int size = file.GetSize();
		if (size > 2048) { // wait for a few packets to be written in case the converter is slow
			stream_mic_sound_private(h_speaker, h_listeners, 0, g_EngineFuncs.Time(), file);
			return;
		}
		
		file.Close();
	}
	
	float waitTime = g_Engine.time - waitTimeStart;
	if (waitTime >= 0 and waitTime < CSMIC_SOUND_TIMEOUT) {
		@g_mic_timers[speaker.entindex()] = @g_Scheduler.SetTimeout("wait_mic_sound", 0.0f, h_speaker, h_listeners, spkPath, waitTimeStart);
	} else {
		g_PlayerFuncs.ClientPrint(cast<CBasePlayer@>(speaker), HUD_PRINTNOTIFY, "[ChatSounds] Failed to play sound on mic.");
	}
}

// send a message to the steam_voice program
void send_steam_voice_message(string msg) {	
	File@ file = g_FileSystem.OpenFile( micsound_file, OpenFile::APPEND );
	
	if (!file.IsOpen()) {
		string text = "[ChatSounds] Failed to open: " + micsound_file + "\n";
		println(text);
		g_Log.PrintF(text);
		return;
	}
	
	print("[ChatSoundsOut] " + msg + "\n");
	file.Write(msg + "\n");
	file.Close();
}

float calcNextPacketDelay(float playback_start_time, float packetNum) {
	float serverTime = g_EngineFuncs.Time();
	float ideal_next_packet_time = playback_start_time + packetNum*(g_packet_delay - 0.0001f); // slightly fast to prevent mic getting quiet/choppy
	return (ideal_next_packet_time - serverTime) - g_Engine.frametime;
}

void stream_mic_sound_private(EHandle h_speaker, array<EHandle>@ h_listeners, int packetNum, float playback_start_time, File@ file) {	
	CBasePlayer@ speaker = cast<CBasePlayer@>(h_speaker.GetEntity());
	if (speaker is null or !speaker.IsConnected() or g_pause_mic_audio) {
		file.Close();
		return;
	}
	
	string line;
	file.ReadLine(line);
	if (line.IsEmpty() or file.EOFReached()) {
		file.Close();
		return;
	}
	
	VoicePacket packet = parse_mic_packet(line);
	
	for (uint i = 0; i < h_listeners.size(); i++) {
		CBasePlayer@ listener = cast<CBasePlayer@>(h_listeners[i].GetEntity());
		
		if (listener is null or !listener.IsConnected()) {
			continue;
		}
		
		packet.send(speaker, listener);
	}
	
	float nextDelay = calcNextPacketDelay(playback_start_time, packetNum);
	
	++packetNum;
	
	if (nextDelay < 0) {
		stream_mic_sound_private(h_speaker, h_listeners, packetNum, playback_start_time, @file);
	} else {
		@g_mic_timers[speaker.entindex()] = @g_Scheduler.SetTimeout("stream_mic_sound_private", nextDelay, h_speaker, h_listeners, packetNum, playback_start_time, @file);
	}	
}