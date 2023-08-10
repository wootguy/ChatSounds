#include "Stats"
#include "MicSounds"
#include "brap"

// . doesnt work in spectator for loaded sounds

// config
const string g_SoundFile      = "scripts/plugins/cfg/ChatSounds.txt"; // permanently precached sounds
const string g_extraSoundFile = "scripts/plugins/cfg/ChatSounds_extra.txt"; // sounds that players can choose to precache
const string soundStatsFile   = "scripts/plugins/store/cs_stats.txt"; // .csstats
const string soundListsFile   = "scripts/plugins/store/cs_lists.txt"; // personal sound lists
const string g_spk_folder     = "scripts/plugins/temp"; // path to sound files converted to NetworkMessage format
const string micsound_file    = "scripts/plugins/store/_tocs.txt";
const uint g_BaseDelay        = 6666;
const array<string> g_sprites = {'sprites/flower.spr', 'sprites/nyanpasu2.spr', 'sprites/flowergag.spr'};
const uint MAX_PERSONAL_SOUNDS = 8;
const float CSMIC_SOUND_TIMEOUT = 1.0f; // wait this many seconds before giving up on waiting for a sound to convert
const float CSMIC_VOLUME = 22; // global volume setting for sounds played over mic, 15 = 100% volume of normal sounds
const float CSRELIABLE_DELAY = 10.0f; // seconds to wait after player join to enable reliable packets (fixes overflows/desyncs)
/////////

// For .csmic to work, run the steam_voice program with the following arguments:
// "chatsounds" <path_to_micsound_file> <path_to_chatsound_txt> <path_to_Sven_Coop_folder>

class ChatSound {
	string trigger;
	string fpath;
	bool alwaysPrecache;
	
	// for sounds that players need to select
	bool isPrecached = false;
	bool isStreaming = false; // prevent parallel loading
	
	ChatSound() {}
	
	ChatSound(string trigger, string fpath, bool alwaysPrecache) {
		const uint triggerLen = trigger.Length();
		// if (trigger == "smithlol")
					// g_PlayerFuncs.SayTextAll(null, "Found smith! length for word "+triggerLen+"\n");
	
		for (uint i = 0; i < triggerLen; i++)
		{
			string triggerSequence = trigger.SubString(0, i+1);
			
			dictionary@ wordList;
			if( !g_SoundBeginTrie.exists(triggerSequence) )
			{
				@wordList = dictionary();
				g_SoundBeginTrie[triggerSequence] = @wordList;
			}
			else
			{
				@wordList = cast<dictionary@>( g_SoundBeginTrie[triggerSequence] );
			}
			// wordList.insertLast(trigger);
			wordList[trigger] = true;
			
			for (uint j = 1; j < triggerLen-i+1; j++)
			{
				string containSequence = trigger.SubString(i, j);
				// if (trigger == "smithlol")
					// g_PlayerFuncs.SayTextAll(null, "Found smith! for word "+containSequence+" "+(i)+":"+j+"\n");
				
				if( !g_SoundContainTrie.exists(containSequence) )
				{
					@wordList = dictionary();
					g_SoundContainTrie[containSequence] = @wordList;
				}
				else
				{
					@wordList = cast<dictionary@>( g_SoundContainTrie[containSequence] );
				}
				
				// bool alreadyExists = false;
				// for(uint k = 0; k < wordList.length(); k++)
				// {
					// if (wordList[k] == trigger)
					// {
						// alreadyExists = true;
						// break;
					// }
						
				// }
				// if (!alreadyExists)
					// wordList.insertLast(trigger);
				if (!wordList.exists(trigger))
					wordList[trigger] = true;
			}
		}
		
		this.trigger = trigger;
		this.fpath = fpath;
		this.alwaysPrecache = alwaysPrecache;
		
		if (this.alwaysPrecache) {
			isPrecached = true;
		}
	}
}

enum MicModes {
	MICMODE_OFF, 	// don't ever use mic audio to play chatsounds
	MICMODE_LOCAL,	// use mic audio to play unloaded sounds + attenuate volume
	MICMODE_GLOBAL,	// use mic audio to play unloaded sounds + max volume everywhere in the map
	MICMODE_SUPER_GLOBAL	// play all sounds at max volume everywhere in the map
}

class PlayerState {
	array<string> soundList;
	array<string> muteList;
	int micMode = MICMODE_LOCAL;
	int volume = 100;
	int pitch = 100;
	Vector brapColor = Vector(200, 255, 200);
	bool reliablePackets = false; // helps with lossy connections
	float lastLaggyCmd = 0; // for cooldowns on commands that could lag the serber to death if spammed
	float joinTime; // for delaying reliable packets
	
	string lastSound;
	SOUND_CHANNEL lastSoundChan;
	
	string lastEmittedSound = ""; // last chatsound played by the user
	float lastEmittedTime; // time of last chatsound played by user
}

uint g_Delay = g_BaseDelay;
bool precached = false;
dictionary g_SoundList;
dictionary g_SoundBeginTrie;
dictionary g_SoundContainTrie;
dictionary g_playerStates;
array<uint> g_ChatTimes(33);
array<string> @g_SoundListKeys;
array<string> g_normalSoundKeys;
array<string> g_extraSoundKeys;
size_t filesize;
string g_last_precache_map; // avoid precaching new sounds on restarted maps, or else fastdl will break
array<string> g_last_map_players; // players that were present during the previous level change
bool g_pause_mic_audio = false;
uint g_micsound_id = 0; // used with .cstop.
string g_previous_map = "";
bool g_stats_enabled = false;

CClientCommand g_ListSounds("listsounds", "List all chat sounds", @listsoundscmd);
CClientCommand g_ListSounds2("listsounds2", "List extra chat sounds", @listsounds2cmd);
CClientCommand g_CSPreview("cs", "Chat sound preview", @cspreviewcmd);
CClientCommand g_CSLoad("csload", "Chat sound loader", @csloadcmd);
CClientCommand g_CSUnload("csunload", "Chat sound loader", @csunloadcmd);
CClientCommand g_CSList("cslist", "Show your personal sounds", @listpersonalcmd);
CClientCommand g_CSMic("csmic", "Toggle microphone sound mode", @csmiccmd);
CClientCommand g_CSPitch("cspitch", "Sets the pitch at which your ChatSounds play (25-255)", @cspitch);
CClientCommand g_CSStats("csstats", "Sound usage stats", @cs_stats);
CClientCommand g_CSMute("csmute", "Mute sounds from player", @csmute);
CClientCommand g_CSVol("csvol", "Change sound volume for all players", @csvol);
CClientCommand g_writecsstats("writecsstats", "Write sound usage stats", @writecsstats_cmd, ConCommandFlag::AdminOnly);
CClientCommand g_cspause("cspause", "Pause chatsound mic audio to fix lag", @cspause, ConCommandFlag::AdminOnly);
CClientCommand g_csreliable("csreliable", "Reliable packets for unloaded sounds", @csreliable);
CClientCommand g_cstop("cstop", "Stop playing mic sounds", @cstop);

CConCommand _extMute( "csmute_ext", "Mute from other plugin", @extMute ); // for muting from another plugin

void PluginInit() {
    g_Module.ScriptInfo.SetAuthor("incognico + w00tguy");
    g_Module.ScriptInfo.SetContactInfo("https://discord.gg/qfZxWAd");

    g_Hooks.RegisterHook(Hooks::Player::ClientSay, @ClientSay);
    g_Hooks.RegisterHook(Hooks::Player::ClientDisconnect, @ClientDisconnect);
    g_Hooks.RegisterHook(Hooks::Player::ClientPutInServer, @ClientPutInServer);
    g_Hooks.RegisterHook( Hooks::Game::MapChange, @MapChange );

    ReadSounds();
	if (g_stats_enabled)
		loadUsageStats();
	loadPersonalSoundLists();
	update_mic_sounds_config_all();
	
	g_Scheduler.SetInterval("brap_think", 0.05f, -1);
}

void PluginExit() {
	if (g_stats_enabled)
		writeUsageStats();
	writePersonalSoundLists();
	brap_unload();
}

void stop_crying()
{
	for( int i = 1; i <= g_Engine.maxClients; ++i ) 
	{
		CBasePlayer@ target = g_PlayerFuncs.FindPlayerByIndex( i );

		if (target is null or !target.IsConnected())
			continue;
			
		PlayerState@ tstate = getPlayerState(target);
		
		if (g_Engine.time - tstate.lastEmittedTime < 14.f && tstate.lastEmittedSound.SubString(0, 3) == "cry")
		{
			stop_mic_sound(target);
			g_SoundSystem.StopSound(target.edict(), tstate.lastSoundChan, tstate.lastSound);
			// g_PlayerFuncs.SayTextAll(null, "Stopped player from crying!\n");
		}
	}
}

void kiss_effect(EHandle h_plr, int kissLeft) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null or !plr.IsConnected()) {
		return;
	}
	
	te_playersprites(plr, "sprites/heart.spr", 2);

	if (kissLeft > 0) {
		g_Scheduler.SetTimeout("kiss_effect", 0.2f, h_plr, kissLeft-1);
	}
}

void te_killplayerattachments(CBasePlayer@ plr, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) {
	NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);
	m.WriteByte(TE_KILLPLAYERATTACHMENTS);
	m.WriteByte(plr.entindex());
	m.End();
}

void MapInit() {
    g_ChatTimes.resize(33);
    g_any_stats_changed = false;
    g_Delay = g_BaseDelay;
	
	if (g_Engine.mapname != g_last_precache_map) {
		if (SoundsChanged())
			ReadSounds();
		
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
        g_Game.PrecacheModel(g_sprites[i]);
    }
	
	g_Game.PrecacheModel("sprites/heart.spr");

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
			int micMode = atoi(parts[1]);
			if (micMode < 0) micMode = 0;
			if (micMode > 3) micMode = 3;
			
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
			
			if (state.soundList.size() == 0 and state.micMode == MICMODE_LOCAL) {
				continue;
			}
			
			string line = fileSteamId + "\\" + state.micMode + "\\";
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
	if (g_stats_enabled)
		writeUsageStats();
	writePersonalSoundLists();
	
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
	g_SoundBeginTrie.deleteAll();
	g_SoundContainTrie.deleteAll();
	g_normalSoundKeys.resize(0);
	g_extraSoundKeys.resize(0);
	
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

			ChatSound sound = ChatSound(parsed[0], parsed[1], !parsingExtraSounds);
			
			if (parsingExtraSounds) {
				g_extraSoundKeys.insertLast(parsed[0]);
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

    g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\nType '.listsounds2' to see extra sounds that can be selectively loaded.\n\n");
}

// sounds that need to be selected before using
void listsounds2(CBasePlayer@ plr, const CCommand@ args) {
	array<string> lines;
	
	PlayerState@ state = getPlayerState(plr);
	
	float delta = g_Engine.time - state.lastLaggyCmd;
	if (delta < 5 and delta >= 0) {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "Wait a few seconds before using that command.\n");
		return;
	}
	state.lastLaggyCmd = g_Engine.time;

    string sMessage = "";
	
	if (args.ArgC() > 1)
	{
		const string trigger = args.Arg(1);

		if (g_SoundBeginTrie.exists(trigger))
		{
			lines.insertLast("\nSOUND TRIGGERS STARTING WITH '"+trigger+"'\n");
			lines.insertLast("------------------------\n");
			array<string> triggers = cast<dictionary@>( g_SoundBeginTrie[trigger] ).getKeys();
			// triggers.sortAsc();

			uint triggersAdded = 0;
			uint msgLen = 0;
			for (uint i = 0; i < triggers.length(); i++)
			{
				const string str = triggers[i];
				const uint strLen = str.Length();
				
				if (msgLen + strLen > 30)
				{
					lines.insertLast(sMessage);
					lines.insertLast("\n");
					sMessage = "";
					msgLen = 0;
				}
				if (msgLen > 0)
					sMessage += " | ";
				
				sMessage += str;
				msgLen += strLen;
				
				// g_PlayerFuncs.SayTextAll(null, "Found begin trigger: "+triggers[i]+" for keyword: "+trigger+" "+sMessage+"\n");
			}
			
			lines.insertLast(sMessage);
			lines.insertLast("\n");
			sMessage = "";
		}
		else
		{
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "\nCouldn't find any sound that begins with that sequence.\n");
		}
		
		
		if (g_SoundContainTrie.exists(trigger))
		{
			lines.insertLast("\nSOUND TRIGGERS CONTAINING '"+trigger+"'\n");
			lines.insertLast("------------------------\n");
			array<string> triggers = cast<dictionary@>( g_SoundContainTrie[trigger] ).getKeys();

			uint triggersAdded = 0;
			uint msgLen = 0;
			for (uint i = 0; i < triggers.length(); i++)
			{
				const string str = triggers[i];
				const uint strLen = str.Length();
				
				if (msgLen + strLen > 30)
				{
					lines.insertLast(sMessage);
					lines.insertLast("\n");
					sMessage = "";
					msgLen = 0;
				}
				if (msgLen > 0)
					sMessage += " | ";
				
				sMessage += str;
				msgLen += strLen;
				
				// g_PlayerFuncs.SayTextAll(null, "Found contain trigger: "+triggers[i]+" for keyword: "+trigger+" "+sMessage+"\n");
			}
			
			lines.insertLast(sMessage);
			lines.insertLast("\n");
			sMessage = "";
		}
		else
		{
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "Couldn't find any sound that contains with that sequence.\n");
		}
		
		lines.insertLast("\n");
		delay_print(EHandle(plr), lines, 24);
		return;
	}
	
	// lines.insertLast("Amount of sounds: "+g_extraSoundKeys.length());
	lines.insertLast("\nEXTRA SOUND TRIGGERS\n");
    lines.insertLast("------------------------\n");

    for (uint i = 1; i < g_extraSoundKeys.length()+1; ++i) {
        sMessage += g_extraSoundKeys[i-1] + " | ";

        if (i % 5 == 0) {
            sMessage.Resize(sMessage.Length() -2);
            lines.insertLast(sMessage);
            lines.insertLast("\n");
            sMessage = "";
        }
    }

    if (sMessage.Length() > 2) {
        sMessage.Resize(sMessage.Length() -2);
        lines.insertLast(sMessage + "\n");
    }

    lines.insertLast("\nThese sounds need to be selected with '.csload' before they can be used.\n");
    lines.insertLast("Unloaded sounds can be previewed with the '.cs' command, or streamed by default with the '.csmic' command.\n");
    lines.insertLast("Type '.listsounds' to see the list of sounds that are always loaded.\n\n");

	delay_print(EHandle(plr), lines, 24);
}

void cspreviewcmd(const CCommand@ pArgs) {
    CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
    cspreview(pPlayer, pArgs);
}

void csloadcmd(const CCommand@ pArgs) {
    CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
    csload(pPlayer, pArgs);
}

void csunloadcmd(const CCommand@ pArgs) {
    CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
    csunload(pPlayer, pArgs);
}

void listsoundscmd(const CCommand@ pArgs) {
    CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
    listsounds(pPlayer, pArgs);
}

void listsounds2cmd(const CCommand@ pArgs) {
    CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
    listsounds2(pPlayer, pArgs);
}

void listpersonalcmd(const CCommand@ pArgs) {
    CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
    listpersonal(pPlayer, pArgs);
}

dictionary g_loadedSounds; // defined globally so anon function can see it
void listpersonal(CBasePlayer@ plr, const CCommand@ args) {
	PlayerState@ stateCaller = getPlayerState(plr);
	float delta = g_Engine.time - stateCaller.lastLaggyCmd;
	if (delta < 3 and delta >= 0) {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "Wait a few seconds before using that command.\n");
		return;
	}
	stateCaller.lastLaggyCmd = g_Engine.time;
	
	showPersonalSounds(plr);
	g_loadedSounds.deleteAll();	
	
	for (int i = 1; i <= g_Engine.maxClients; i++) {
		CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (p is null or !p.IsConnected()) {
			continue;
		}

		PlayerState@ state = getPlayerState(p);
		
		for (uint k = 0; k < state.soundList.size(); k++) {
			if (!g_SoundList.exists(state.soundList[k])) {
				continue;
			}
			if (g_loadedSounds.exists(state.soundList[k])) {
				array<string>@ loaders = cast<array<string>@>(g_loadedSounds[state.soundList[k]]);
				loaders.insertLast(p.pev.netname);
			} else {
				array<string> loaders;
				loaders.insertLast(p.pev.netname);
				g_loadedSounds[state.soundList[k]] = loaders;
			}
		}
	}
	
	array<string> loadedSoundKeys = g_loadedSounds.getKeys();
	if (loadedSoundKeys.size() > 0) {
		loadedSoundKeys.sort(function(a,b) {
			return cast<array<string>@>(g_loadedSounds[a]).size() > cast<array<string>@>(g_loadedSounds[b]).size();
		});
	}
	
	
	array<string> printLines;
	
	printLines.insertLast("\nBelow are sounds favorited by active players.\n");
    printLines.insertLast("\n     Sound               Users");
    printLines.insertLast("\n--------------------------------------------\n");
	
	int position = 1;
	for (uint i = 0; i < loadedSoundKeys.size(); i++) {
		string posString = position;
		if (position < 100) {
            posString = " " + posString;
        }
        if (position < 10) {
            posString = " " + posString;
        }
        position++;
		
		string line = posString + ") " + loadedSoundKeys[i];
        
        int padding = 20 - loadedSoundKeys[i].Length();
        for (int k = 0; k < padding; k++)
            line += " ";
        
		array<string>@ userNames = cast<array<string>@>(g_loadedSounds[loadedSoundKeys[i]]);
		userNames.sortAsc();
		string userStr;
		
		for (uint k = 0; k < userNames.size(); k++) {
			string userName = userNames[k];
			if (userName.Length() > 10) {
				userName = userName.SubString(0, 9) + "-";
			}
			
			userStr += (k > 0 ? ", " : "") + userNames[k];
		}

        line += userStr + "\n";
        printLines.insertLast(line);
	}
	
	delay_print(EHandle(plr), printLines, 12);
}

void cspitch(const CCommand@ pArgs) {
    CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
    const string steamId = g_EngineFuncs.GetPlayerAuthId(pPlayer.edict());

    if (pArgs.ArgC() < 2)
        return;

    setpitch(steamId, pArgs[1], pPlayer);
}

void extMute(const CCommand@ args) {
	println("[ChatSounds] extmute " + args[1] + " " + args[2] + " " + args[3]);
	CBasePlayer@ muter = g_PlayerFuncs.FindPlayerByIndex(atoi(args[1]));
	string targetid = args[2].ToLowercase();
	bool shouldMute = atoi(args[3]) != 0;
	
	PlayerState@ state = getPlayerState(muter);	
	
	if (shouldMute) {
		if (state.muteList.find(targetid) == -1) {
			state.muteList.insertLast(targetid);
			
			g_EngineFuncs.ServerCommand("stop_mic_sound " + muter.entindex() + " 0\n");
			g_EngineFuncs.ServerExecute();
		}
	} else {
		if (state.muteList.find(targetid) != -1) {
			state.muteList.removeAt(state.muteList.find(targetid));
		}
	}
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

void cspause(const CCommand@ pArgs) {
    CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
   
	g_pause_mic_audio = !g_pause_mic_audio;
	
	if (g_pause_mic_audio) {
		g_PlayerFuncs.ClientPrint(pPlayer, HUD_PRINTTALK, "[ChatSounds] Mic audio paused.\n");
	} else {
		g_PlayerFuncs.ClientPrint(pPlayer, HUD_PRINTTALK, "[ChatSounds] Mic audio resumed.\n");
	}
}

void csreliable(const CCommand@ pArgs) {
    CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
   
	PlayerState@ state = getPlayerState(pPlayer);
	state.reliablePackets = !state.reliablePackets;
	if (pArgs.ArgC() > 1) {
		state.reliablePackets = atoi(pArgs[1]) != 0;
	}
	
	update_mic_sounds_config(pPlayer);
	g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Reliable packets " + (state.reliablePackets ? "enabled" : "disabled") + ".\n");
}

void cstop(const CCommand@ pArgs) {
    CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
	g_EngineFuncs.ServerCommand("stop_mic_sound " + pPlayer.entindex() + " 0\n");
	g_EngineFuncs.ServerExecute();
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

void play_chat_sound(CBasePlayer@ speaker, SOUND_CHANNEL channel, ChatSound@ snd, float volume, float attenuation, int pitch) {
	PlayerState@ speakerState = getPlayerState(speaker);
	speakerState.lastEmittedSound = snd.trigger;
	speakerState.lastEmittedTime = g_Engine.time;

	string speakerId = g_EngineFuncs.GetPlayerAuthId(speaker.edict());
	speakerId = speakerId.ToLowercase();
	
	array<EHandle> micListeners;
	
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
			if (snd.isPrecached && state.micMode != MICMODE_SUPER_GLOBAL) {
				g_SoundSystem.PlaySound(speaker.edict(), channel, snd.fpath, localVol, attenuation, 0, pitch, plr.entindex());
				state.lastSound = snd.fpath;
				state.lastSoundChan = channel;
			} else if (state.micMode > 0) {
				micListeners.insertLast(EHandle(plr));
			}
		}
	}
	
	if (micListeners.size() > 0) {
		play_mic_sound(EHandle(speaker), micListeners, snd, pitch);
	}
}

void te_playersprites(CBasePlayer@ target, 
	string sprite="sprites/bubble.spr", uint8 count=16,
	NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null)
{
	NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);
	m.WriteByte(TE_PLAYERSPRITES);
	m.WriteShort(target.entindex());
	m.WriteShort(g_EngineFuncs.ModelIndex(sprite));
	m.WriteByte(count);
	m.WriteByte(0); // "size variation" - has no effect
	m.End();
}

void delayGagIcon(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	
	if (plr is null or !plr.IsConnected())
		return;
	
	plr.ShowOverheadSprite(g_sprites[2], 51.0f, 1.5f);
}

HookReturnCode ClientSay(SayParameters@ pParams) {
    const CCommand@ pArguments = pParams.GetArguments();
	CBasePlayer@ pPlayer = pParams.GetPlayer();
	PlayerState@ state = getPlayerState(pPlayer);
	
    if (pArguments.ArgC() > 0) {
        string soundArgUpper = pArguments.Arg(0);
        string soundArg = pArguments.Arg(0).ToLowercase();
        string pitchArg = pArguments.ArgC() > 1 ? pArguments.Arg(1) : "";
		
		if (int(pitchArg.Find("%")) != -1) {
			pitchArg = pitchArg.Replace("%", "%%");
		}

		if (soundArg == ".") {
			player_say(pPlayer, pParams.GetCommand());
			pParams.ShouldHide = true;
			stop_mic_sound(pPlayer);
			g_SoundSystem.StopSound(pPlayer.edict(), state.lastSoundChan, state.lastSound);
			return HOOK_CONTINUE;
		}

        if (g_SoundList.exists(soundArg)) {
			ChatSound@ chatsound = cast<ChatSound@>(g_SoundList[soundArg]);
			
            const string steamId = g_EngineFuncs.GetPlayerAuthId(pPlayer.edict());
            const int idx = pPlayer.entindex();

            int pitch = state.pitch;
            const bool pitchOverride = isNumeric(pitchArg) && pArguments.ArgC() == 2;
			const bool allowrelay = ( (!pitchOverride && pArguments.ArgC() >= 2) || (soundArg == 'yes!' || soundArg == 'no!') && pArguments.ArgC() == 1 ); // can't take care of pitch override for yes!/no! here
                
            if (pitchOverride) {
                pitch = clampPitch(atoi(pitchArg));
            }
			
			if (!chatsound.isPrecached and state.micMode == MICMODE_OFF) {
				string msg = "[ChatSounds] '" + soundArg + "' is unloaded. ";
				
				array<string>@ personalSoundList = getPersonalSoundList(pPlayer);
				
				if (personalSoundList.find(soundArg) != -1) {
					msg += "Wait for a different map before using it, or enable .csmic";
				} else {
					msg += "Request it using the .csload command, or enable .csmic";
				}
				
				g_PlayerFuncs.ClientPrint(pPlayer, HUD_PRINTNOTIFY, msg + "\n");
				
				// uhoh this code duplicated below
				if (allowrelay)
                    return HOOK_CONTINUE;
                else if (pitchOverride)
                    player_say(pPlayer, soundArgUpper); // hide the pitch modifier
                else
                    player_say(pPlayer, pParams.GetCommand());
				
				pParams.ShouldHide = true;
				return HOOK_CONTINUE;
			}

            const uint t = uint(g_EngineFuncs.Time()*1000);
            const uint d = t - g_ChatTimes[idx];

            if (d < g_Delay) {
                const float w = float(g_Delay - d) / 1000.0f;
                g_PlayerFuncs.ClientPrint(pPlayer, HUD_PRINTCENTER, "Wait " + format_float(w) + " seconds\n");

                if (allowrelay)
                    return HOOK_CONTINUE;
                else if (pitchOverride)
                    player_say(pPlayer, soundArgUpper); // hide the pitch modifier
                else
                    player_say(pPlayer, pParams.GetCommand());

				te_killplayerattachments(pPlayer);
				g_Scheduler.SetTimeout("delayGagIcon", 0.1f, EHandle(pPlayer));
				
                pParams.ShouldHide = true;
            }
            else {
                logSoundStat(pPlayer, soundArg);
				g_ChatTimes[idx] = t;
				
                if (soundArg == 'medic' || soundArg == 'meedic') {
                    pPlayer.ShowOverheadSprite('sprites/saveme.spr', 51.0f, 3.5f);
					play_chat_sound(pPlayer, CHAN_STATIC, chatsound, 1.0f, 0.2f, Math.RandomLong(35, 220));
				}
                else {
                    if (precached) {
                        pPlayer.ShowOverheadSprite( g_sprites[Math.RandomLong(0, 1)], 56.0f, 2.5f);
                    }
					
                    const float volume      = 1.0f; // increased volume from .75 since converting stereo sounds to mono made them quiet
                    const float attenuation = 0.4f; // less = bigger sound range
                    play_chat_sound(pPlayer, CHAN_VOICE, chatsound, volume, attenuation, pitch);
					
					if (soundArg == 'kiss') {
						kiss_effect(EHandle(pPlayer), 6);
					}
					if (soundArg == 'kiss2') {
						kiss_effect(EHandle(pPlayer), 1);
					}
					
					if (soundArg == "stopcrying" || soundArg == "stopcrying2" || soundArg == "stopwhine" || soundArg == "dontcry" || soundArg == "dontcry2") {
						// stop_crying();
						g_Scheduler.SetTimeout("stop_crying", 2.f); //delay it so they can hear the player say "stop crying" before doing so
					}
					/*
					if (soundArg == 'bonk' and pitchArg.Length() > 0) {
						string targetid = pitchArg;
						targetid = targetid.ToLowercase();
						CBasePlayer@ target = getBonkTarget(pPlayer, targetid);
						
						if (target !is null and target.IsConnected()) {
							PlayerState@ tstate = getPlayerState(target);
							g_PlayerFuncs.ClientPrintAll(HUD_PRINTNOTIFY, "[ChatSounds] " + pPlayer.pev.netname + " bonked " + target.pev.netname + ".\n");
							stop_mic_sound(target);
							g_SoundSystem.StopSound(target.edict(), tstate.lastSoundChan, tstate.lastSound);
						}
					}
					*/
                }
				
				if (soundArg == 'toot' || soundArg == 'tooot' || soundArg == 'brap' || soundArg == 'tootrape' || soundArg == 'braprape' || soundArg == "bloodbrap" || soundArg == "bloodbraprape" || soundArg == "braplong") {
					do_brap(pPlayer, soundArg, pitch);
				}
				if (soundArg == 'sniff' || soundArg == 'snifff' || soundArg == 'sniffrape') {
					do_sniff(pPlayer, soundArg, pitch);
				}

                

                if (allowrelay)
                    return HOOK_CONTINUE;
                else if (pitchOverride)
                    player_say(pPlayer, soundArgUpper); // hide the pitch modifier
                else
                    player_say(pPlayer, pParams.GetCommand());

                pParams.ShouldHide = true;
            }
        }
        else if (pArguments.ArgC() > 1 && soundArg == '.cspitch') {
            const string steamId = g_EngineFuncs.GetPlayerAuthId(pPlayer.edict());
            pParams.ShouldHide = true;
            setpitch(steamId, pArguments[1], pPlayer);
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.csmute') {
            const string steamId = g_EngineFuncs.GetPlayerAuthId(pPlayer.edict());
            pParams.ShouldHide = true;
            setmute(steamId, pArguments[1], pPlayer);
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.csvol') {
            const string steamId = g_EngineFuncs.GetPlayerAuthId(pPlayer.edict());
            pParams.ShouldHide = true;
            setvol(steamId, pArguments[1], pPlayer);
        }
        else if (pArguments.ArgC() > 0 && soundArg == '.csstats') {
			pParams.ShouldHide = true;
			if (g_stats_enabled) {
				g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Usage stats sent to your console.\n");
				showSoundStats(pPlayer, pArguments.Arg(1));
			} else {
				g_PlayerFuncs.ClientPrint(pPlayer, HUD_PRINTTALK, "Chat sound stats are disabled.\n");
			}
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.csload') {
			csload(pPlayer, pArguments);
            pParams.ShouldHide = true;
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.csunload') {
			csunload(pPlayer, pArguments);
            pParams.ShouldHide = true;
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.csreliable') {
			state.reliablePackets = !state.reliablePackets;
			if (pArguments.ArgC() > 1) {
				state.reliablePackets = atoi(pArguments[1]) != 0;
			}
			update_mic_sounds_config(pPlayer);
			g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Reliable packets " + (state.reliablePackets ? "enabled" : "disabled") + ".\n");
            pParams.ShouldHide = true;
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.cstop') {
			g_EngineFuncs.ServerCommand("stop_mic_sound " + pPlayer.entindex() + " 0\n");
			g_EngineFuncs.ServerExecute();
            pParams.ShouldHide = true;
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.cs') {
			cspreview(pPlayer, pArguments);
            pParams.ShouldHide = true;
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.listsounds') {
			g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Sound list sent to your console.\n");
			listsounds(pPlayer, pArguments);
            pParams.ShouldHide = true;
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.listsounds2') {
			g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Sound list sent to your console.\n");
			listsounds2(pPlayer, pArguments);
            pParams.ShouldHide = true;
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.csmic') {
			csmic(pPlayer, pArguments);
            pParams.ShouldHide = true;
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.cslist') {
			listpersonal(pPlayer, pArguments);
            pParams.ShouldHide = true;
        }
		else if (pArguments.ArgC() > 0 && soundArg == '.brapcolor') {
			brapcolor(pPlayer, pArguments);
            pParams.ShouldHide = true;
        }
    }

    return HOOK_CONTINUE;
}

void delay_reliable_enable(EHandle h_plr, string steamId) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	PlayerState@ state = cast<PlayerState@>( g_playerStates[steamId] );
	state.reliablePackets = true;
	
	if (plr !is null) {
		update_mic_sounds_config(plr);
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTNOTIFY, "[ChatSounds] Reliable packets started.\n");
	}
}

HookReturnCode ClientPutInServer(CBasePlayer@ pPlayer) {
    g_Delay = g_Delay + 333;
	
	PlayerState@ state = getPlayerState(pPlayer);
	state.joinTime = g_EngineFuncs.Time();
	
	// don't set reliable flag until player fully loads to prevent desyncs/overflows
	if (state.reliablePackets) {
		state.reliablePackets = false;
		string steamId = g_EngineFuncs.GetPlayerAuthId( pPlayer.edict() );
		g_Scheduler.SetTimeout("delay_reliable_enable", CSRELIABLE_DELAY, EHandle(pPlayer), steamId);
	}
	
	update_mic_sounds_config(pPlayer);
	
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

void csunloadMenuCallback(CTextMenu@ menu, CBasePlayer@ plr, int page, const CTextMenuItem@ item) {
	if (item is null or plr is null) {
		return;
	}
	
	string replaceStr;
	item.m_pUserData.retrieve(replaceStr);
	
	array<string> parts = replaceStr.Split(",");
	
	removePersonalSound(plr, replaceStr);
	g_PlayerFuncs.SayText(plr, "[ChatSounds] Unloaded " + replaceStr + "\n");
	g_Scheduler.SetTimeout("open_unload_menu", 0.0f, EHandle(plr));
}

void showPersonalSounds(CBasePlayer@ plr) {
	array<string> soundList = getPersonalSoundList(plr);
	soundList.sortAsc();
	
	string msg = "[ChatSounds] Your sounds (" + soundList.size() + "/" + MAX_PERSONAL_SOUNDS + "): ";
	for (uint i = 0; i < soundList.size(); i++) {
		msg += (i > 0 ? " " : "") + soundList[i];
	}
	
	g_PlayerFuncs.SayText(plr, msg + "\n");
	
	
}

void csmic(CBasePlayer@ plr, const CCommand@ args) {
	PlayerState@ state = getPlayerState(plr);
	
	int newMode = 0;
	
	if (args.ArgC() > 1) {
		newMode = atoi(args[1]);
		if (newMode > 3) newMode = 3;
		if (newMode < 0) newMode = 0;
	} else {
		g_PlayerFuncs.SayText(plr, "Usage: .csmic [0-3]\n");
		g_PlayerFuncs.SayText(plr, "  0 (DISABLED) = Unloaded sounds must be loaded to be heard.\n");
		g_PlayerFuncs.SayText(plr, "  1 (LOCAL) = Unloaded sounds played on mic. Volume fades with distance.\n");
		g_PlayerFuncs.SayText(plr, "  2 (GLOBAL) = Unloaded sounds played on mic. No volume fade.\n");
		g_PlayerFuncs.SayText(plr, "  3 (SUPER GLOBAL) = ALL sounds played on mic. No volume fade.\n");
		g_PlayerFuncs.SayText(plr, "Your mode is currently: " + state.micMode + "\n");
		return;
	}
	
	state.micMode = newMode;
	
	if (newMode == MICMODE_SUPER_GLOBAL) {
		g_PlayerFuncs.SayText(plr, "[ChatSounds] Super global mode enabled. ALL sounds will be played on mic at max volume everywhere in the map.\n");
	}
	else if (newMode == MICMODE_GLOBAL) {
		g_PlayerFuncs.SayText(plr, "[ChatSounds] Global mic mode enabled. Unloaded sounds will be played on mic at max volume everywhere in the map.\n");
	} else if (newMode == MICMODE_LOCAL) {
		g_PlayerFuncs.SayText(plr, "[ChatSounds] Local mic mode enabled. Unloaded sounds will be played on mic at a volume determined by distance.\n");
	} else {
		g_EngineFuncs.ServerCommand("stop_mic_sound " + plr.entindex() + " 0\n");
		g_EngineFuncs.ServerExecute();
		g_PlayerFuncs.SayText(plr, "[ChatSounds] Mic mode disabled. Unloaded sounds must now be loaded for you to hear them.\n");
	}
	
	update_mic_sounds_config(plr);
}

void cspreview(CBasePlayer@ plr, const CCommand@ args) {
	if (args.ArgC() == 1) {
		g_PlayerFuncs.SayText(plr, "[ChatSounds] Type the name of a sound after '.cs' to preview it. Only you can hear this.\n");
		return;
	}
	
	PlayerState@ state = getPlayerState(plr);
	float delta = g_Engine.time - state.lastLaggyCmd;
	if (delta < 1 and delta >= 0) {
		g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, "Wait a second before using that command.\n");
		return;
	}
	state.lastLaggyCmd = g_Engine.time;
	
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
			play_mic_sound(EHandle(plr), {EHandle(plr)}, chatsound, 100);
			g_PlayerFuncs.SayText(plr, "[ChatSounds] Previewing '" + wantSound + "'. This sound is not loaded.\n");
		}

	} else {
		g_PlayerFuncs.SayText(plr, "[ChatSounds] '" + wantSound + "' is not a chat sound.\n");
	}
}

void csload(CBasePlayer@ plr, const CCommand@ args) {
	if (args.ArgC() == 1) {
		g_PlayerFuncs.SayText(plr, 'Say ".csload brap" to add the brap sound to your personal sound list.\n');
		g_PlayerFuncs.SayText(plr, 'Say ".csload brap ting uhoh" to replace your sound list with the given sounds.\n');
		g_PlayerFuncs.SayText(plr, 'Say ".listsounds2" to see loadable sounds.\n');
		g_PlayerFuncs.SayText(plr, 'Say ".cs brap" to preview a sound (no cooldown + only you can hear).\n');
		g_PlayerFuncs.SayText(plr, 'Say ".csmic" to hear unloaded sounds via microphone.\n');
		
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

void csunload(CBasePlayer@ plr, const CCommand@ args) {	
	open_unload_menu(EHandle(plr));
}

void open_unload_menu(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}
	
	array<string> soundList = getPersonalSoundList(plr);
		
	if (soundList.size() == 0) {
		g_PlayerFuncs.SayText(plr, "[ChatSounds] You have no personal sounds to unload.\n");
		return;
	}	
	
	int eidx = plr.entindex();
	
	@g_menus[eidx] = CTextMenu(@csunloadMenuCallback);
	g_menus[eidx].SetTitle("\\ySelect a sound to unload:");
	
	soundList.sortAsc();
	for (uint i = 0; i < soundList.size(); i++) {
		g_menus[eidx].AddItem("\\w" + soundList[i] + "\\y", any(soundList[i]));
	}
	
	g_menus[eidx].Register();
	g_menus[eidx].Open(0, 0, plr);
}

void setpitch(const string steamId, const string val, CBasePlayer@ pPlayer) {
	PlayerState@ state = getPlayerState(pPlayer);
    state.pitch = clampPitch(atoi(val));
    g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Pitch set to: " + state.pitch + ".\n");
}

CBasePlayer@ getBonkTarget(CBasePlayer@ caller, string name)
{
	name = name.ToLowercase();
	int partialMatches = 0;
	CBasePlayer@ partialMatch;
	
	for (int i = 1; i <= g_Engine.maxClients; i++) {
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		const string steamId = g_EngineFuncs.GetPlayerAuthId(plr.edict()).ToLowercase();
		
		string plrName = string(plr.pev.netname).ToLowercase();
		if (plrName == name || steamId == name)
			return plr;
		else if (plrName.Find(name) != uint(-1))
		{
			@partialMatch = plr;
			partialMatches++;
		}
	}
	
	if (partialMatches == 1) {
		return partialMatch;
	} else if (partialMatches > 1) {
		g_PlayerFuncs.ClientPrint(caller, HUD_PRINTNOTIFY, '[ChatSounds] Bonk failed. There are ' + partialMatches + ' players that have "' + name + '" in their name. Be more specific.\n');
	} else {
		g_PlayerFuncs.ClientPrint(caller, HUD_PRINTNOTIFY, '[ChatSounds] Bonk failed. There is no player named "' + name + '".\n');
	}
	
	return null;
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
	
	if (val == "\\all") {
		int numMutes = 0;
		
		for (int i = 1; i <= g_Engine.maxClients; i++) {
			CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
			
			if (plr is null or !plr.IsConnected() or plr.entindex() == pPlayer.entindex()) {
				continue;
			}

			string id = g_EngineFuncs.GetPlayerAuthId(plr.edict()).ToLowercase();
			
			if (state.muteList.find(id) == -1) {
				state.muteList.insertLast(id);
				numMutes ++;
			}
		}
		
		if (numMutes > 0) {
			g_EngineFuncs.ServerCommand("stop_mic_sound " + pPlayer.entindex() + " 0\n");
			g_EngineFuncs.ServerExecute();
			g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Added " + numMutes + " player(s) to mute list.\n");
		} else {
			g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] You've already muted everyone here.\n");
		}
		
		return;
	}
	
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
		
		g_EngineFuncs.ServerCommand("stop_mic_sound " + pPlayer.entindex() + " 0\n");
		g_EngineFuncs.ServerExecute();
		
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
	if (newvol > 500) newvol = 500;
	
	state.volume = newvol;
	
	if (state.volume <= 100)
		g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Volume set to " + newvol + "%\n");
	else
		g_PlayerFuncs.SayText(pPlayer, "[ChatSounds] Volume set to " + newvol + "% (only microphone sounds can play above 100% volume)\n");
	update_mic_sounds_config(pPlayer);
}

const int clampPitch(const int val) {
    return Math.clamp(25, 255, val);
}

const string format_float(const float f) {
    const uint decimal = uint(((f - int(f)) * 10)) % 10;
    return "" + int(f) + "." + decimal;
}
