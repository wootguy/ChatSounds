#include "crc32"

float g_packet_delay = 0.05f;

// a packet that can be played up to 32 times in parallel
class ComboPacket {
	array<VoicePacket> packets;
	
	void send(CBasePlayer@ speaker, CBasePlayer@ listener) {
		int comboId = speaker.entindex() % 32;
		packets[comboId].send(speaker, listener);
	}
}

class VoicePacket {
	uint size = 0;
	
	array<string> sdata;
	array<uint32> ldata;
	array<uint8> data;
	
	VoicePacket() {}
	
	VoicePacket(array<uint8>@ inputBytes) {
		// "compress" data for faster writing later
		string sdat = "";
		for (uint i = 0; i < inputBytes.size(); i++) {
			uint8 bval = inputBytes[i];
			data.insertLast(bval);
			
			// combine into 32bit ints for faster writing later
			if (data.size() == 4) {
				uint32 val = (data[3] << 24) + (data[2] << 16) + (data[1] << 8) + data[0];
				ldata.insertLast(val);
				data.resize(0);
			}
			
			// combine into string for even faster writing later
			if (bval == 0) {
				sdata.insertLast(sdat);
				ldata.resize(0);
				data.resize(0);
				sdat = "";
			} else {
				sdat += HEX_CODES[bval];
			}
		}
		
		size = inputBytes.size();
	}
	
	void send(CBasePlayer@ speaker, CBasePlayer@ listener) {
		bool send_reliable_packets = false; // TODO: load this setting from radio plugin?
	
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
array<ComboPacket> load_mic_sound(string fpath) {
	array<ComboPacket> packets; 
	
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

ComboPacket parse_mic_packet(string line) {
	array<uint8> data; // original packet bytes, as read from file
	
	for (uint i = 0; i < line.Length()-1; i += 2) {
		uint n1 = char_to_nibble[ uint(line[i]) ];
		uint n2 = char_to_nibble[ uint(line[i + 1]) ];
		uint8 bval = (n1 << 4) + n2;
		data.insertLast(bval);
	}
	
	int sz = data.size();
	
	ComboPacket comboPacket;
	
	for (uint i = 0; i < 8; i++) {
		data[0] = data[0] + 1; // increment steamid64 so that the packet can be played in parallel with others
		
		// get checksum for all bytes excluding the checksum bytes
		uint32 crc32 = crc32_get(data, sz-4); 
		data[sz-4] = (crc32 >> 0) & 0xff;
		data[sz-3] = (crc32 >> 8) & 0xff;
		data[sz-2] = (crc32 >> 16) & 0xff;
		data[sz-1] = (crc32 >> 24) & 0xff;
		
		comboPacket.packets.insertLast(VoicePacket(data));
	}
	
	println("PARSE " + line);
	
	return comboPacket;
}

void play_mic_sound(EHandle h_speaker, EHandle h_listener, ChatSound@ sound) {
	if (sound.previewData.size() == 0 and !sound.isStreaming) {
		// sound hasn't been loaded yet. Stream the data instead of loading all at once so the server doesn't freeze
		File@ file = openMicSoundfile(sound.fpath_spk);
	
		if (file is null) {
			return;
		}
		
		sound.isStreaming = true;
		stream_mic_sound_private(h_speaker, h_listener, 0, g_EngineFuncs.Time(), sound, file);
	} else {
		if (sound.isStreaming) {
			// wait a little for the packet buffer to fill up
			g_Scheduler.SetTimeout("play_mic_sound_private", 0.2f, h_speaker, h_listener, @sound.previewData, 0, g_EngineFuncs.Time()+0.2f);
		} else {
			play_mic_sound_private(h_speaker, h_listener, @sound.previewData, 0, g_EngineFuncs.Time());
		}
	}
}

float calcNextPacketDelay(float playback_start_time, float packetNum) {
	float serverTime = g_EngineFuncs.Time();
	float ideal_next_packet_time = playback_start_time + packetNum*(g_packet_delay - 0.0001f); // slightly fast to prevent mic getting quiet/choppy
	return (ideal_next_packet_time - serverTime) - g_Engine.frametime;
}

void play_mic_sound_private(EHandle h_speaker, EHandle h_listener, array<ComboPacket>@ packets, int packetNum, float playback_start_time) {	
	CBasePlayer@ speaker = cast<CBasePlayer@>(h_speaker.GetEntity());
	CBasePlayer@ listener = cast<CBasePlayer@>(h_listener.GetEntity());
	
	if (speaker is null or !speaker.IsConnected() or listener is null or !listener.IsConnected()) {
		return;
	}

	packets[packetNum].send(speaker, listener);
	
	float nextDelay = calcNextPacketDelay(playback_start_time, packetNum);
	
	if (++packetNum >= int(packets.size())) {
		return;
	}
	
	if (nextDelay < 0) {
		play_mic_sound_private(h_speaker, h_listener, @packets, packetNum, playback_start_time);
	} else {
		g_Scheduler.SetTimeout("play_mic_sound_private", nextDelay, h_speaker, h_listener, @packets, packetNum, playback_start_time);
	}	
}

void stream_mic_sound_private(EHandle h_speaker, EHandle h_listener, int packetNum, float playback_start_time, ChatSound@ sound, File@ file) {	
	CBasePlayer@ speaker = cast<CBasePlayer@>(h_speaker.GetEntity());
	CBasePlayer@ listener = cast<CBasePlayer@>(h_listener.GetEntity());
	
	if (speaker is null or !speaker.IsConnected() or listener is null or !listener.IsConnected()) {
		return;
	}
	
	string line;
	file.ReadLine(line);
	if (line.IsEmpty() or file.EOFReached()) {
		file.Close();
		sound.isStreaming = false;
		return;
	}
	
	ComboPacket packet = parse_mic_packet(line);
	sound.previewData.insertLast(packet); // save to sound file for faster playing next time

	packet.send(speaker, listener);
	
	float nextDelay = calcNextPacketDelay(playback_start_time, packetNum);
	
	++packetNum;
	
	if (nextDelay < 0) {
		stream_mic_sound_private(h_speaker, h_listener, packetNum, playback_start_time, @sound, @file);
	} else {
		g_Scheduler.SetTimeout("stream_mic_sound_private", nextDelay, h_speaker, h_listener, packetNum, playback_start_time, @sound, @file);
	}	
}