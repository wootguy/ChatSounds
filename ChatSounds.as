#include "Stats"
#include "MicSounds"
#include "../peepeepoopoo/brap"

// config
const string g_SoundFile      = "scripts/plugins/cfg/ChatSounds.txt"; // permanently precached sounds
const string g_extraSoundFile = "scripts/plugins/cfg/ChatSounds_extra.txt"; // sounds that players can choose to precache
const string soundStatsFile   = "scripts/plugins/store/cs_stats.txt"; // .csstats
const string soundListsFile   = "scripts/plugins/store/cs_lists.txt"; // personal sound lists
const uint g_BaseDelay        = 6666;
const array<string> g_sprites = {'sprites/flower.spr', 'sprites/nyanpasu2.spr'};
const uint MAX_PERSONAL_SOUNDS = 8;
/////////

class ChatSound {
	string fpath;
	bool alwaysPrecache;
	
	// for sounds that players need to select
	bool isPrecached = false;
	array<VoicePacket> previewData; // voice data for previewing the chatsound before it's loaded
	
	ChatSound() {}
	
	ChatSound(string fpath, bool alwaysPrecache) {
		this.fpath = fpath;
		this.alwaysPrecache = alwaysPrecache;
		
		if (this.alwaysPrecache) {
			isPrecached = true;
		}
	}
}

class PlayerState {
	array<string> soundList;
	array<string> muteList;
	bool micMode = false;
	int volume = 100;
	int pitch = 100;
}

uint g_Delay = g_BaseDelay;
bool precached = false;
dictionary g_SoundList;
dictionary g_playerStates;
array<uint> g_ChatTimes(33);
array<string> @g_SoundListKeys;
array<string> g_normalSoundKeys;
array<string> g_extraSoundKeys;
size_t filesize;
string g_last_precache_map; // avoid precaching new sounds on restarted maps, or else fastdl will break
array<string> g_last_map_players; // players that were present during the previous level change

CClientCommand g_ListSounds("listsounds", "List all chat sounds", @listsoundscmd);
CClientCommand g_ListSounds2("listsounds2", "List extra chat sounds", @listsounds2cmd);
CClientCommand g_CSPreview("cs", "Chat sound preview", @cspreviewcmd);
CClientCommand g_CSLoad("csload", "Chat sound loader", @csloadcmd);
CClientCommand g_CSMic("csmic", "Toggle microphone sound mode", @csloadcmd);
CClientCommand g_CSPitch("cspitch", "Sets the pitch at which your ChatSounds play (25-255)", @cspitch);
CClientCommand g_CSStats("csstats", "Sound usage stats", @cs_stats);
CClientCommand g_CSMute("csmute", "Mute sounds from player", @csmute);
CClientCommand g_CSVol("csvol", "Change sound volume for all players", @csvol);
CClientCommand g_writecsstats("writecsstats", "Write sound usage stats", @writecsstats_cmd, ConCommandFlag::AdminOnly);

void PluginInit() {
    g_Module.ScriptInfo.SetAuthor("incognico + w00tguy");
    g_Module.ScriptInfo.SetContactInfo("https://discord.gg/qfZxWAd");

    g_Hooks.RegisterHook(Hooks::Player::ClientSay, @ClientSay);
    g_Hooks.RegisterHook(Hooks::Player::ClientDisconnect, @ClientDisconnect);
    g_Hooks.RegisterHook(Hooks::Player::ClientPutInServer, @ClientPutInServer);
    g_Hooks.RegisterHook( Hooks::Game::MapChange, @MapChange );

    ReadSounds();
    loadUsageStats();
	loadPersonalSoundLists();
	
	g_Scheduler.SetInterval("brap_think", 0.05f, -1);
}

void PluginExit() {
    writeUsageStats();
	writePersonalSoundLists();
	brap_unload();
}

void MapInit() {
    if (SoundsChanged())
        ReadSounds();

    g_ChatTimes.resize(33);
    g_any_stats_changed = false;
    g_Delay = g_BaseDelay;
	
	if (g_Engine.mapname != g_last_precache_map) {
		updatePrecachedSounds();
		g_last_precache_map = g_Engine.mapname;
	}

    for (uint i = 0; i < g_SoundListKeys.length(); ++i) {
		ChatSound@ chatsound = cast<ChatSound@>(g_SoundList[g_SoundListKeys[i]]);
		
		if (!chatsound.isPrecached) {
			continue;
		}
		
        g_Game.PrecacheGeneric("sound/" + chatsound.fpath);
        g_SoundSystem.PrecacheSound(chatsound.fpath);
    }

    for (uint i = 0; i < g_sprites.length(); ++i) {
        g_Game.PrecacheGeneric(g_sprites[i]);
        g_Game.PrecacheModel(g_sprites[i]);
    }

    precached = true;
	
	brap_precache();
}

void updatePrecachedSounds() {
	for (uint i = 0; i < g_extraSoundKeys.length(); ++i) {
		ChatSound@ chatsound = cast<ChatSound@>(g_SoundList[g_extraSoundKeys[i]]);
		chatsound.isPrecached = false;
    }
	
	for (uint k = 0; k < g_last_map_players.size(); k++) {
		string steamId = g_last_map_players[k];		
		PlayerState@ state = getPlayerState(steamId);
		
		for (uint i = 0; i < state.soundList.size(); i++) {
			if (!g_SoundList.exists(state.soundList[i])) {
				continue;
			}
			
			ChatSound@ chatsound = cast<ChatSound@>(g_SoundList[state.soundList[i]]);
			chatsound.isPrecached = true;
		}
	}
}

PlayerState@ getPlayerState(CBasePlayer@ plr) {	
	string steamId = g_EngineFuncs.GetPlayerAuthId( plr.edict() );
	if (steamId == 'STEAM_ID_LAN') {
		steamId = plr.pev.netname;
	}

	return getPlayerState(steamId);
}

PlayerState@ getPlayerState(string steamId) {
	if ( !g_playerStates.exists(steamId) )
	{
		PlayerState state;
		g_playerStates[steamId] = state;
	}
	return cast<PlayerState@>( g_playerStates[steamId] );
}

void loadPersonalSoundLists() {
    g_stats.resize(0);

    DateTime start = DateTime();

    File@ file = g_FileSystem.OpenFile(soundListsFile, OpenFile::READ);

    if(file !is null && file.IsOpen())
    {
        while(!file.EOFReached())
        {
            string line;
            file.ReadLine(line);
                
            line.Trim();
            if (line.Length() == 0)
                continue;
            
            array<string> parts = line.Split("\\");
			bool micMode = atoi(parts[1]) != 0;
			array<string> sounds = (parts[2].Length() > 0) ? parts[2].Split(" ") : array<string>();
			string steamid = "STEAM_0:" + parts[0];
			
			PlayerState@ state = getPlayerState(steamid);
			state.soundList = sounds;
			state.micMode = micMode;
        }

        file.Close();
    } else {
        println("chat sound lists file not found: " + soundListsFile + "\n");
    }
    
    const float diff = TimeDifference(DateTime(), start).GetTimeDifference();
    println("Finished chatsound list load in " + diff + " seconds");
}

void writePersonalSoundLists() {    
    File@ f = g_FileSystem.OpenFile( soundListsFile, OpenFile::WRITE);
	
	DateTime start = DateTime();
    
    if( f.IsOpen() )
    {       
		array<string> steamIds = g_playerStates.getKeys();
		
        int numWritten = 0;
        for (uint i = 0; i < steamIds.size(); i++) {
			string steamId = steamIds[i];
			string fileSteamId = steamId;
			fileSteamId = fileSteamId.SubString(8); // strip STEAM_0:
			PlayerState@ state = cast<PlayerState@>(g_playerStates[steamId]);
			
			if (state.soundList.size() == 0 and !state.micMode) {
				continue;
			}
			
			println("WRITE CUZ " + state.soundList.size() + " " + state.micMode);
			
			string line = fileSteamId + "\\" + (state.micMode ? "1" : "0") + "\\";
			for (uint k = 0; k < state.soundList.size(); k++) {
				line += (k > 0 ? " " : "") + state.soundList[k];
			}
			f.Write(line + "\n");
			numWritten++;
        }
        f.Close();
        
        println("Wrote " + numWritten + " personal chatsound lists");
    }
    else
        println("Failed to open chat sound lists file: " + soundListsFile + "\n");
        
    const float diff = TimeDifference(DateTime(), start).GetTimeDifference();
    println("Wrote chatsound lists in " + diff + " seconds");
}

HookReturnCode MapChange() {
    writeUsageStats();
	
	g_last_map_players.resize(0);
	
	for (int i = 1; i <= g_Engine.maxClients; i++) {
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}

		const string steamId = g_EngineFuncs.GetPlayerAuthId(plr.edict());
		g_last_map_players.insertLast(steamId);
	}
	
    return HOOK_CONTINUE;
}

void ReadSounds() {
    g_SoundList.deleteAll();
	
	bool parsingExtraSounds = false;

    File@ file = g_FileSystem.OpenFile(g_SoundFile, OpenFile::READ);
    filesize = file.GetSize();
    if (file !is null && file.IsOpen()) {
        while(!file.EOFReached()) {
            string sLine;
            file.ReadLine(sLine);

            sLine.Trim();
            if (sLine.IsEmpty() or sLine[0] == '/')
                continue;

			if (sLine.Find("[extra_sounds]") == 0) {
				parsingExtraSounds = true;
				continue;
			}

            const array<string> parsed = sLine.Split(" ");
            if (parsed.length() < 2)
                continue;

			ChatSound sound = ChatSound(parsed[1], !parsingExtraSounds);			
			
			if (parsingExtraSounds) {
				g_extraSoundKeys.insertLast(parsed[0]);
				string spk_path = sound.fpath;
				sound.previewData = load_mic_sound(spk_path.Replace(".wav", ".spk"));
			} else {
				g_normalSoundKeys.insertLast(parsed[0]);
			}
			
			g_SoundList[parsed[0]] = sound;
        }
        file.Close();
        @g_SoundListKeys = g_SoundList.getKeys();
        g_SoundListKeys.sortAsc();
        g_normalSoundKeys.sortAsc();
        g_extraSoundKeys.sortAsc();
    }
}

const bool SoundsChanged() {
    File@ file = g_FileSystem.OpenFile(g_SoundFile, OpenFile::READ);
    const bool changed = (file.GetSize() != filesize) ? true : false;
    file.Close();
    return changed;
}

void listsounds(CBasePlayer@ plr, const CCommand@ args) {
    g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\nAVAILABLE SOUND TRIGGERS\n");
    g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "------------------------\n");

    string sMessage = "";

    for (uint i = 1; i < g_normalSoundKeys.length()+1; ++i) {
        sMessage += g_normalSoundKeys[i-1] + " | ";

        if (i % 5 == 0) {
            sMessage.Resize(sMessage.Length() -2);
            g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, sMessage);
            g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\n");
            sMessage = "";
        }
    }

    if (sMessage.Length() > 2) {
        sMessage.Resize(sMessage.Length() -2);
        g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, sMessage + "\n");
    }

    g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\nThese sounds are always loaded.\n");
    g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "Type '.listsounds2' to see extra sounds that can be selectively loaded.\n\n");
}

// sounds that need to be selected before using
void listsounds2(CBasePlayer@ plr, const CCommand@ args) {
    g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\nEXTRA SOUND TRIGGERS\n");
    g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "------------------------\n");

    string sMessage = "";

    for (uint i = 1; i < g_extraSoundKeys.length()+1; ++i) {
        sMessage += g_extraSoundKeys[i-1] + " | ";

        if (i % 5 == 0) {
            sMessage.Resize(sMessage.Length() -2);
            g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, sMessage);
            g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\n");
            sMessage = "";
        }
    }

    if (sMessage.Length() > 2) {
        sMessage.Resize(sMessage.Length() -2);
        g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, sMessage + "\n");
    }

    g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\nThese sounds need to be selected with '.csload' before they can be used.\n");
    g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "Type '.listsounds' to see the list of sounds that are always loaded.\n\n");
}

void cspreviewcmd(const CCommand@ pArgs) {
    CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
    cspreview(pPlayer, pArgs);
}

void csloadcmd(const CCommand@ pArgs) {
    CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
    csload(pPlayer, pArgs);
}

void listsoundscmd(const CCommand@ pArgs) {
    CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
    listsounds(pPlayer, pArgs);
}

void listsounds2cmd(const CCommand@ pArgs) {
    CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
    listsounds2(pPlayer, pArgs);
}

void cspitch(const CCommand@ pArgs) {
    CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
    const string steamId = g_EngineFuncs.GetPlayerAuthId(pPlayer.edict());

    if (pArgs.ArgC() < 2)
        return;

    setpitch(steamId, pArgs[1], pPlayer);
}

void csmute(const CCommand@ pArgs) {
    CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
    const string steamId = g_EngineFuncs.GetPlayerAuthId(pPlayer.edict());

    setmute(steamId, pArgs[1], pPlayer);
}

void csvol(const CCommand@ pArgs) {
    CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
    const string steamId = g_EngineFuncs.GetPlayerAuthId(pPlayer.edict());

    setvol(steamId, pArgs[1], pPlayer);
}

void csmiccmd(const CCommand@ pArgs) {
    CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
    csmic(pPlayer, pArgs);
}

bool isNumeric(string arg) {
    if (arg.Length() == 0) {
        return false;
    }

    if (!isdigit(arg[0]) and arg[0] != "-") {
        return false;
    }

    for (uint i = 1; i < arg.Length(); i++) {
        if (!isdigit(arg[i])) {
            return false;
        }
    }
    
    return true;
}

void print(string text) { g_Game.AlertMessage( at_console, text); }
void println(string text) { print(text + "\n"); }

void player_say(CBaseEntity@ plr, string msg) {
    NetworkMessage m(MSG_ALL, NetworkMessages::NetworkMessageType(74), null);
        m.WriteByte(plr.entindex());
        m.WriteByte(2); // tell the client to color the player name according to team
        m.WriteString("" + plr.pev.netname + ": " + msg + "\n");
    m.End();

    // fake the server log line and print
    g_Game.AlertMessage(at_logged, "\"%1<%2><%3><player>\" say \"%4\"\n", plr.pev.netname, string(g_EngineFuncs.GetPlayerUserId(plr.edict())), g_EngineFuncs.GetPlayerAuthId(plr.edict()), msg);
    g_EngineFuncs.ServerPrint("" + plr.pev.netname + ": " + msg + "\n");
}

/* void player_say_delayed(EHandle h_plr, string msg) {
    CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
    if (plr !is null and plr.IsConnected()) {
        player_say(plr, msg);
    }
} */

void play_chat_sound(CBasePlayer@ speaker, SOUND_CHANNEL channel, ChatSound snd, float volume, float attenuation, int pitch) {
	string speakerId = g_EngineFuncs.GetPlayerAuthId(speaker.edict());
	speakerId = speakerId.ToLowercase();
	
	for (int i = 1; i <= g_Engine.maxClients; i++) {
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		PlayerState@ state = getPlayerState(plr);
		if (state.muteList.find(speakerId) != -1) {
			continue; // player muted the speaker
		}
		
		int vol = state.volume;
		float localVol = float(vol / 100.0f)*volume;
		
		if (localVol > 0) {
			if (snd.isPrecached) {
				g_SoundSystem.PlaySound(speaker.edict(), channel, snd.fpath, localVol, attenuation, 0, pitch, plr.entindex());
			} else if (state.micMode) {
				play_mic_sound(EHandle(speaker), EHandle(plr), snd.previewData);
			}
		}
	}
}

HookReturnCode ClientSay(SayParameters@ pParams) {
    const CCommand@ pArguments = pParams.GetArguments();

    if (pArguments.ArgC() > 0) {
        const string soundArgUpper = pArguments.Arg(0);
        const string soundArg = pArguments.Arg(0).ToLowercase();
        const string pitchArg = pArguments.ArgC() > 1 ? pArguments.Arg(1) : "";

        if (g_SoundList.exists(soundArg)) {
			ChatSound@ chatsound = cast<ChatSound@>(g_SoundList[soundArg]);
            CBasePlayer@ pPlayer = pParams.GetPlayer();
			PlayerState@ state = getPlayerState(pPlayer);
            const string steamId = g_EngineFuncs.GetPlayerAuthId(pPlayer.edict());
            const int idx = pPlayer.entindex();

            int pitch = state.pitch;
            const bool pitchOverride = isNumeric(pitchArg) && pArguments.ArgC() == 2;
            if (pitchOverride) {
                pitch = clampPitch(atoi(pitchArg));
            }
			
			if (!chatsound.isPrecached and !state.micMode) {
				string msg = "[ChatSounds] '" + soundArg + "' is unloaded. ";
				
				array<string>@ personalSoundList = getPersonalSoundList(pPlayer);
				
				if (personalSoundList.find(soundArg) != -1) {
					msg += "Wait for a different map before using it.";
				} else {
					msg += "Request it using the '.csload' command.";
				}
				
				g_PlayerFuncs.SayText(pPlayer, msg + "\n");
				//play_mic_sound(EHandle(pPlayer), chatsound.previewData);
				
				if (pitchOverride || pArguments.ArgC() == 1) {
                    pParams.ShouldHide = true;
                }
				
				return HOOK_CONTINUE;
			}

            const uint t = uint(g_EngineFuncs.Time()*1000);
            const uint d = t - g_ChatTimes[idx];

            if (d < g_Delay) {
                const float w = float(g_Delay - d) / 1000.0f;
                g_PlayerFuncs.ClientPrint(pPlayer, HUD_PRINTCENTER, "Wait " + format_float(w) + " seconds\n");

                if (pitchOverride || pArguments.ArgC() == 1) {
                    pParams.ShouldHide = true;
                }
            }
            else {
                logSoundStat(pPlayer, soundArg);

                if (soundArg == 'medic' || soundArg == 'meedic') {
                    pPlayer.ShowOverheadSprite('sprites/saveme.spr', 51.0f, 3.5f);
					play_chat_sound(pPlayer, CHAN_STATIC, chatsound, 1.0f, 0.2f, Math.RandomLong(35, 220));
				}
                else {
                    if (precached) {
                        pPlayer.ShowOverheadSprite( g_sprites[Math.RandomLong(0, g_sprites.length()-1)], 56.0f, 2.5f);
                    }
                    const float volume      = 1.0f; // increased volume from .75 since converting stereo sounds to mono made them quiet
                    const float attenuation = 0.4f; // less = bigger sound range
                    play_chat_sound(pPlayer, CHAN_VOICE, chatsound, volume, attenuation, pitch);
                }
				
				if (soundArg == 'toot' || soundArg == 'tooot' || soundArg == 'brap' || soundArg == 'tootrape' || soundArg == 'braprape') {
					do_brap(pPlayer, soundArg, pitch);
				}
				if (soundArg == 'sniff' || soundArg == 'snifff' || soundArg == 'sniffrape') {
					do_sniff(pPlayer, soundArg, pitch);
				}

                g_ChatTimes[idx] = t;

                const bool allowrelay = ( (!pitchOverride && pArguments.ArgC() >= 2) || (soundArg == 'yes!' || soundArg == 'no!') && pArguments.ArgC() == 1 ); // can't take care of pitch override for yes!/no! here
                if (allowrelay) {
                    return HOOK_CONTINUE;
                }
                else if (pitchOverride) {
                    player_say(pPlayer, soundArgUpper); // hide the pitch modifier
                }
                else {
                    player_say(pPlayer, pParams.GetCommand());
                }

                pParams.ShouldHide = true;
            }
        }
        else if (pArguments.ArgC() > 1 && soundArg == '.cspitch') {
            CBasePlayer@ pPlayer = pParams.GetPlayer();
            const string steamId = g_EngineFuncs.GetPlayerAuthId(pPlayer.edict());
            pParams.ShouldHide = true;
            setpitch(steamId, pArguments[1], pPlayer);
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.csmute') {
            CBasePlayer@ pPlayer = pParams.GetPlayer();
            const string steamId = g_EngineFuncs.GetPlayerAuthId(pPlayer.edict());
            pParams.ShouldHide = true;
            setmute(steamId, pArguments[1], pPlayer);
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.csvol') {
            CBasePlayer@ pPlayer = pParams.GetPlayer();
            const string steamId = g_EngineFuncs.GetPlayerAuthId(pPlayer.edict());
            pParams.ShouldHide = true;
            setvol(steamId, pArguments[1], pPlayer);
        }
        else if (pArguments.ArgC() > 0 && soundArg == '.csstats') {
            CBasePlayer@ pPlayer = pParams.GetPlayer();
            g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Usage stats sent to your console.\n");
            pParams.ShouldHide = true;
            showSoundStats(pPlayer, pArguments.Arg(1));
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.csload') {
            CBasePlayer@ pPlayer = pParams.GetPlayer();
			csload(pPlayer, pArguments);
            pParams.ShouldHide = true;
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.cs') {
            CBasePlayer@ pPlayer = pParams.GetPlayer();
			cspreview(pPlayer, pArguments);
            pParams.ShouldHide = true;
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.listsounds') {
            CBasePlayer@ pPlayer = pParams.GetPlayer();
			g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Sound list sent to your console.\n");
			listsounds(pPlayer, pArguments);
            pParams.ShouldHide = true;
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.listsounds2') {
            CBasePlayer@ pPlayer = pParams.GetPlayer();
			g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Sound list sent to your console.\n");
			listsounds2(pPlayer, pArguments);
            pParams.ShouldHide = true;
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.csmic') {
            CBasePlayer@ pPlayer = pParams.GetPlayer();
			csmic(pPlayer, pArguments);
            pParams.ShouldHide = true;
        }
    }

    return HOOK_CONTINUE;
}

HookReturnCode ClientPutInServer(CBasePlayer@ pPlayer) {
    g_Delay = g_Delay + 333;
    return HOOK_CONTINUE;
}

HookReturnCode ClientDisconnect(CBasePlayer@ pPlayer) {
    g_Delay = g_Delay - 333;
    return HOOK_CONTINUE;
}

void clearSoundList(CBasePlayer@ plr) {
	PlayerState@ state = getPlayerState(plr);
	state.soundList.resize(0);
}

array<string>@ getPersonalSoundList(CBasePlayer@ plr) {
	PlayerState@ state = getPlayerState(plr);
	return state.soundList;
}

bool canAddPersonalSound(CBasePlayer@ plr, string wantSound) {
	const string steamId = g_EngineFuncs.GetPlayerAuthId(plr.edict());
	
	if (g_SoundList.exists(wantSound)) {
		ChatSound@ chatsound = cast<ChatSound@>(g_SoundList[wantSound]);
		
		if (chatsound.alwaysPrecache) {
			g_PlayerFuncs.SayText(plr, "[ChatSounds] '" + wantSound + "' is always loaded. There's no reason to have it in your sound list.");
			return false;
		}

	} else {
		g_PlayerFuncs.SayText(plr, "[ChatSounds] '" + wantSound + "' is not a chat sound.");
		return false;
	}
	
	return true;
}

void addPersonalSound(CBasePlayer@ plr, string sound) {
	PlayerState@ state = getPlayerState(plr);
	state.soundList.insertLast(sound);
}

void removePersonalSound(CBasePlayer@ plr, string sound) {
	PlayerState@ state = getPlayerState(plr);
	int idx = state.soundList.find(sound);
	
	if (idx != -1) {
		state.soundList.removeAt(idx);
	}
}

// Menus need to be defined globally when the plugin is loaded or else paging doesn't work.
// Each player needs their own menu or else paging breaks when someone else opens the menu.
// These also need to be modified directly (not via a local var reference).
array<CTextMenu@> g_menus = {
	null, null, null, null, null, null, null, null,
	null, null, null, null, null, null, null, null,
	null, null, null, null, null, null, null, null,
	null, null, null, null, null, null, null, null,
	null
};

void csloadMenuCallback(CTextMenu@ menu, CBasePlayer@ plr, int page, const CTextMenuItem@ item) {
	if (item is null or plr is null) {
		return;
	}
	
	string replaceStr;
	item.m_pUserData.retrieve(replaceStr);
	
	array<string> parts = replaceStr.Split(",");
	
	removePersonalSound(plr, parts[0]);
	addPersonalSound(plr, parts[1]);
	showPersonalSounds(plr);
}

void showPersonalSounds(CBasePlayer@ plr) {
	array<string> soundList = getPersonalSoundList(plr);
	soundList.sortAsc();
	
	string msg = "[ChatSounds] Your sounds: ";
	for (uint i = 0; i < soundList.size(); i++) {
		msg += (i > 0 ? " " : "") + soundList[i];
	}
	
	g_PlayerFuncs.SayText(plr, msg + "\n");
}

void csmic(CBasePlayer@ plr, const CCommand@ args) {
	PlayerState@ state = getPlayerState(plr);
	
	bool newMode = !state.micMode;
	
	if (args.ArgC() > 1) {
		newMode = args[1] != '0';
	}
	
	state.micMode = newMode;	
	
	if (newMode) {
		g_PlayerFuncs.SayText(plr, "[ChatSounds] Mic mode enabled. Unloaded sounds will be streamed to you via microphone.\n");
	} else {
		g_PlayerFuncs.SayText(plr, "[ChatSounds] Mic mode disabled. Unloaded sounds must be selected to be heard.\n");
	}
}

void cspreview(CBasePlayer@ plr, const CCommand@ args) {
	if (args.ArgC() == 1) {
		g_PlayerFuncs.SayText(plr, "[ChatSounds] Type the name of a sound after '.cs' to preview it. Only you can hear this.\n");
		return;
	}
	
	string wantSound = args[1];
	wantSound = wantSound.ToLowercase();
	
	if (g_SoundList.exists(wantSound)) {
		ChatSound@ chatsound = cast<ChatSound@>(g_SoundList[wantSound]);
		
		if (chatsound.alwaysPrecache) {
			g_SoundSystem.PlaySound(plr.edict(), CHAN_VOICE, chatsound.fpath, 1.0f, 0.4f, 0, 100, plr.entindex());
			g_PlayerFuncs.SayText(plr, "[ChatSounds] Previewing '" + wantSound + "'. This sound is always loaded.\n");
		} else if (chatsound.isPrecached) {
			g_SoundSystem.PlaySound(plr.edict(), CHAN_VOICE, chatsound.fpath, 1.0f, 0.4f, 0, 100, plr.entindex());
			g_PlayerFuncs.SayText(plr, "[ChatSounds] Previewing '" + wantSound + "'. This sound is loaded.\n");
		} else {
			play_mic_sound(EHandle(plr), EHandle(plr), chatsound.previewData);
			g_PlayerFuncs.SayText(plr, "[ChatSounds] Previewing '" + wantSound + "'. This sound is not loaded.\n");
		}

	} else {
		g_PlayerFuncs.SayText(plr, "[ChatSounds] '" + wantSound + "' is not a chat sound.\n");
	}
}

void csload(CBasePlayer@ plr, const CCommand@ args) {
	if (args.ArgC() == 1) {
		g_PlayerFuncs.SayText(plr, "[ChatSounds] Help for the .csload command:\n");
		g_PlayerFuncs.SayText(plr, 'Say ".csload brap" to add the brap sound to your personal sound list.\n');
		g_PlayerFuncs.SayText(plr, 'Say ".csload brap ting uhoh" to replace your sound list with the given sounds.\n');
		g_PlayerFuncs.SayText(plr, 'Say ".cs brap" to preview a sound (only you can hear this).\n');
		g_PlayerFuncs.SayText(plr, 'Say ".csmic" to play unloaded sounds via microphone.\n');
		g_PlayerFuncs.SayText(plr, 'Your personal sounds will load when a new map loads. Restarts don\'t count as a new map.\n');
		return;
	}
	
	if (args.ArgC() == 2) {
		string ret = "";
	
		string wantSound = args[1];
		wantSound = wantSound.ToLowercase();
	
		array<string> soundList = getPersonalSoundList(plr);
		
		if (soundList.find(wantSound) != -1) {
			g_PlayerFuncs.SayText(plr, "[ChatSounds] '" + wantSound + "' is already in your personal sound list.");
			return;
		}
		
		if (soundList.size() == MAX_PERSONAL_SOUNDS) {
			g_PlayerFuncs.SayText(plr, "[ChatSounds] You can't have more than " + MAX_PERSONAL_SOUNDS + " personal sounds.\n");
			int eidx = plr.entindex();
			
			@g_menus[eidx] = CTextMenu(@csloadMenuCallback);
			g_menus[eidx].SetTitle("\\yRemove something to\nmake room for " + wantSound + "?");
			
			soundList.sortAsc();
			for (uint i = 0; i < soundList.size(); i++) {
				g_menus[eidx].AddItem("\\w" + soundList[i] + "\\y", any(soundList[i] + "," + wantSound));
			}
			
			g_menus[eidx].Register();
			g_menus[eidx].Open(0, 0, plr);
			
			return;
		}
	
		if (canAddPersonalSound(plr, wantSound)) {
			addPersonalSound(plr, wantSound);
		} else {
			return;
		}
	} 
	else if (args.ArgC() > 2) {
		string ret = "";
	
		if (args.ArgC() > MAX_PERSONAL_SOUNDS+1) {
			g_PlayerFuncs.SayText(plr, "[ChatSounds] You can't have more than " + MAX_PERSONAL_SOUNDS + " personal sounds.\n");
			return;
		}
	
		clearSoundList(plr);
	
		for (int i = 1; i < args.ArgC(); i++) {
			string wantSound = args[i];
			wantSound = wantSound.ToLowercase();
			
			if (canAddPersonalSound(plr, wantSound)) {
				if (i <= MAX_PERSONAL_SOUNDS) {
					addPersonalSound(plr, wantSound);
				}
			}
		}
	}
	
	showPersonalSounds(plr);
}

void setpitch(const string steamId, const string val, CBasePlayer@ pPlayer) {
	PlayerState@ state = getPlayerState(pPlayer);
    state.pitch = clampPitch(atoi(val));
    g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Pitch set to: " + state.pitch + ".\n");
}

// find a player by name or partial name
CBasePlayer@ getPlayerByName(CBasePlayer@ caller, string name)
{
	name = name.ToLowercase();
	int partialMatches = 0;
	CBasePlayer@ partialMatch;
	CBaseEntity@ ent = null;
	do {
		@ent = g_EntityFuncs.FindEntityByClassname(ent, "player");
		if (ent !is null) {
			CBasePlayer@ plr = cast<CBasePlayer@>(ent);
			string plrName = string(plr.pev.netname).ToLowercase();
			if (plrName == name)
				return plr;
			else if (plrName.Find(name) != uint(-1))
			{
				@partialMatch = plr;
				partialMatches++;
			}
		}
	} while (ent !is null);
	
	if (partialMatches == 1) {
		return partialMatch;
	} else if (partialMatches > 1) {
		g_PlayerFuncs.SayText(caller, '[ChatSounds] Mute failed. There are ' + partialMatches + ' players that have "' + name + '" in their name. Be more specific.\n');
	} else {
		g_PlayerFuncs.SayText(caller, '[ChatSounds] Mute failed. There is no player named "' + name + '".\n');
	}
	
	return null;
}

void setmute(const string steamId, const string val, CBasePlayer@ pPlayer) {
	string targetid = val;
	targetid = targetid.ToLowercase();
	string nicename = "???";
	PlayerState@ state = getPlayerState(steamId);
	
	if (val.Length() == 0) {
		if (state.muteList.size() > 0) {
			state.muteList.resize(0);
			g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Unmuted everyone.\n");
			return;
		} else {
			g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] No one is muted.\n");
			return;
		}
	}
	
	if (targetid.Find("steam_0:") == 0) {
		nicename = targetid;
		nicename.ToUppercase();
	} else {
		CBasePlayer@ target = getPlayerByName(pPlayer, val);
		
		if (target is null) {
			return;
		}
		
		targetid = g_EngineFuncs.GetPlayerAuthId(target.edict());
		targetid = targetid.ToLowercase();
		nicename = target.pev.netname;
	}
	
	if (state.muteList.find(targetid) != -1) {
		state.muteList.removeAt(state.muteList.find(targetid));
		g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Unmuted player: " + nicename + "\n");
	} else {
		if (state.muteList.size() >= 50) {
			g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Can't mute more than 50 players!\n");
			return;
		}
		
		g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Muted player: " + nicename + "\n");
		state.muteList.insertLast(targetid);
	}
}

void setvol(const string steamId, const string val, CBasePlayer@ pPlayer) {
	PlayerState@ state = getPlayerState(steamId);
	
	if (val.Length() == 0) {
		int curVol = state.volume;
		g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Volume is currently at " + curVol + "%\n");
		return;
	}
	
	int newvol = atoi(val);
	if (newvol < 0) newvol = 0;
	if (newvol > 100) newvol = 100;
	
	state.volume = newvol;
	
	g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Volume set to " + newvol + "%\n");
}

const int clampPitch(const int val) {
    return Math.clamp(25, 255, val);
}

const string format_float(const float f) {
    const uint decimal = uint(((f - int(f)) * 10)) % 10;
    return "" + int(f) + "." + decimal;
}
