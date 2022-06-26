//
// .csstats
//

class UserStat {
    string steamid;
    string name;
    int soundCount = 0;
}

class SoundStat {
    string chatTrigger;
    array<UserStat> users;
    int totalUses; // temp for sorting
    bool isValid = false; // does this sound exist?
}

array<SoundStat> g_stats;
dictionary unique_users;

void update_stat_user_name(string steamid, string newname) {
	for (uint i = 0; i < g_stats.size(); i++) {
		for (uint k = 0; k < g_stats[i].users.size(); k++) {
			if (steamid == g_stats[i].users[k].steamid) {
				g_stats[i].users[k].name = newname;
			}
		}
	}
}

void logSoundStat(CBasePlayer@ plr, const string chatTrigger) {
    if (chatTrigger.Length() == 0) {
        return;
    }
    
    const bool debugit = chatTrigger == "ots";
    
    g_any_stats_changed = true;

    string steamid = g_EngineFuncs.GetPlayerAuthId( plr.edict() );
    steamid = steamid.SubString(8); // strip STEAM_0:
    unique_users[steamid] = true;
    
    for (uint i = 0; i < g_stats.size(); i++) {
        if (chatTrigger == g_stats[i].chatTrigger.ToLowercase()) {
            for (uint k = 0; k < g_stats[i].users.size(); k++) {
                if (debugit) println("COMPARE " + steamid + " " + g_stats[i].users[k].steamid);
                
                if (steamid == g_stats[i].users[k].steamid) {
                    g_stats[i].users[k].soundCount++;
					if (g_stats[i].users[k].name != plr.pev.netname) {
						update_stat_user_name(steamid, plr.pev.netname);
					}
                    g_stats[i].totalUses++;
                    if (debugit) println("increase sound count for " + steamid);
                    return;
                }
            }
            
            if (debugit) println("add new user stat " + steamid);
            UserStat newStat;
            newStat.steamid = steamid;
            newStat.name = plr.pev.netname;
            newStat.soundCount = 1;
            g_stats[i].totalUses++;
            g_stats[i].users.insertLast(newStat);
            return;
        }
    }
    
    if (debugit) println("add new sound stat " + chatTrigger);
    UserStat newStat;
    newStat.steamid = steamid;
    newStat.name = plr.pev.netname;
    newStat.soundCount = 1;
    
    SoundStat newVstat;
    newVstat.chatTrigger = chatTrigger;
    newVstat.totalUses = 1;
    newVstat.users.insertLast(newStat);
    
    g_stats.insertLast(newVstat);
}

// only write stats if anything changes (sometimes maps are restarted before anyone can use a sound)
bool g_any_stats_changed = false;

void writeUsageStats() {
    if (!g_any_stats_changed) {
        return;
    }
    DateTime start = DateTime();
    
    File@ f = g_FileSystem.OpenFile( soundStatsFile, OpenFile::WRITE);
    
    if( f.IsOpen() )
    {       
        int numWritten = 0;
        for (uint i = 0; i < g_stats.size(); i++) {         
            f.Write("[" + g_stats[i].chatTrigger + "]\n");
            for (uint k = 0; k < g_stats[i].users.size(); k++) {
                f.Write(g_stats[i].users[k].steamid + "\\" + g_stats[i].users[k].name + "\\" + g_stats[i].users[k].soundCount + "\n");
                numWritten++;
            }
        }
        f.Close();
        
        println("Wrote " + numWritten + " usage stats");
    }
    else
        println("Failed to open chat sound stats file: " + soundStatsFile + "\n");
        
    const float diff = TimeDifference(DateTime(), start).GetTimeDifference();
    println("Wrote chatsound stats in " + diff + " seconds");
}

void loadUsageStats() {
    g_stats.resize(0);

    DateTime start = DateTime();

    string tempSoundName = "";
    array<UserStat> tempUserStats;

    File@ file = g_FileSystem.OpenFile(soundStatsFile, OpenFile::READ);

    if(file !is null && file.IsOpen())
    {
        int numRead = 0;
        int soundCountTotal = 0;
        
        while(!file.EOFReached())
        {
            string sLine;
            file.ReadLine(sLine);
                
            sLine.Trim();
            if (sLine.Length() == 0)
                continue;
            
            if (sLine[0] == '[') {
                if (tempSoundName.Length() > 0) {
                    SoundStat vstat;
                    vstat.chatTrigger = tempSoundName;
                    vstat.users = tempUserStats;
                    vstat.totalUses = soundCountTotal;
                    tempUserStats = array<UserStat>();
                    g_stats.insertLast(vstat);
                    soundCountTotal = 0;
                }
            
                tempSoundName = sLine.Replace("[", "").Replace("]", "");
                continue;
            }
            
            UserStat stat;
            stat.steamid = sLine.Tokenize("\\");
            stat.name = sLine.Tokenize("\\");
            stat.soundCount = atoi(sLine.Tokenize("\\"));
            soundCountTotal += stat.soundCount;
            numRead++;
            unique_users[stat.steamid] = true;
            
            tempUserStats.insertLast(stat);
        }

        if (tempSoundName.Length() > 0) {
            SoundStat vstat;
            vstat.chatTrigger = tempSoundName.ToLowercase();
            vstat.users = tempUserStats;
            vstat.totalUses = soundCountTotal;
            tempUserStats = array<UserStat>();
            g_stats.insertLast(vstat);
            soundCountTotal = 0;
        }
        
        println("Loaded " + numRead + " chat sound stats");

        file.Close();
    } else {
        println("chat sound stats file not found: " + soundStatsFile + "\n");
    }
    
    for (uint i = 0; i < g_SoundListKeys.size(); i++) {
        bool hasStat = false;
        
        const string lowerSound = g_SoundListKeys[i].ToLowercase();
        
        for (uint k = 0; k < g_stats.size(); k++) {
            if (g_stats[k].chatTrigger.ToLowercase() == lowerSound) {
                hasStat = true;
                g_stats[k].isValid = true;
                break;
            }
        }
        
        if (!hasStat) {
            SoundStat vstat;
            vstat.chatTrigger = lowerSound;
            vstat.isValid = true;
            g_stats.insertLast(vstat);
        }
    }
    
    const float diff = TimeDifference(DateTime(), start).GetTimeDifference();
    println("Finished load in " + diff + " seconds");
}

void showSoundStats(CBasePlayer@ plr, string chatTrigger) {
    if (chatTrigger.Length() > 0) {
        showSoundStats_singleSound(plr, chatTrigger);
        return;
    }
    chatTrigger = chatTrigger.ToLowercase();
    
	if (g_stats.size() > 1) {
		g_stats.sort(function(a,b) { return a.totalUses > b.totalUses; });
	}
	
	array<string> statPrints;
	
    statPrints.insertLast("\nUsage stats for " + g_SoundListKeys.size() + " chat sounds\n");
    statPrints.insertLast("\n       Sound               Uses     Users");
    statPrints.insertLast("\n--------------------------------------------\n");

    int position = 1;
    int allSoundUses = 0;
    for (uint i = 0; i < g_stats.size(); i++) {
        if (!g_stats[i].isValid) {
            continue; // chat sound not loaded
        }
    
		ChatSound@ sound = cast<ChatSound@>(g_SoundList[g_stats[i].chatTrigger]);
		if (sound is null) {
			continue;
		}
		
		string posString = position;
		if (position < 100) {
            posString = " " + posString;
        }
        if (position < 10) {
            posString = " " + posString;
        }
        position++;
		
        string line = (sound.isPrecached ? "* " : "  ") + posString + ") " + g_stats[i].chatTrigger;
      
        
        int padding = 20 - g_stats[i].chatTrigger.Length();
        for (int k = 0; k < padding; k++)
            line += " ";
        
        string count = g_stats[i].totalUses;
        padding = 9 - count.Length();
        for (int k = 0; k < padding; k++)
            count += " ";
        line += count;
        
        string users = g_stats[i].users.size();
        padding = 8 - users.Length();
        for (int k = 0; k < padding; k++)
            users += " ";
        line += users;
        
        line += "\n";
        statPrints.insertLast(line);
        
        allSoundUses += g_stats[i].totalUses;
    }

    string totals = allSoundUses;
    int padding = 9 - totals.Length();
    for (int k = 0; k < padding; k++)
        totals += " ";
    totals += unique_users.size();

    statPrints.insertLast("--------------------------------------------\n");
    statPrints.insertLast("                    Total:  " + totals + "\n");
    statPrints.insertLast("\n*      = Sound is currently loaded.");
    statPrints.insertLast("\nUses   = Number of times a chat sound has been used.");
    statPrints.insertLast("\nUsers  = Number of unique players that have used the sound.\n\n");
	
	delay_print(EHandle(plr), statPrints, 24);
}

// prevent overflows by sending messages in chunks
void delay_print(EHandle h_plr, array<string>@ messages, int chunkSize) {
	float delay = 0;
	
	for (uint i = 0; i < messages.size(); i += chunkSize) {
		int start = i;
		int end = i + chunkSize;
		
		if (end > int(messages.size())) {
			end = messages.size();
		}
		
		g_Scheduler.SetTimeout("delay_print", delay, h_plr, @messages, start, end);
		delay += 0.1f;
	}
}

void delay_print(EHandle h_plr, array<string>@ messages, int start, int end) {
	CBasePlayer @ plr = cast < CBasePlayer @ > (h_plr.GetEntity());
	if (plr !is null) {
		for (int i = start; i < end; i++) {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, messages[i]);
		}
	}
}

void printUserStat(CBasePlayer@ plr, int k, UserStat@ stat, bool isYou) {
    int position = k+1;
    string line = "" + position + ") ";
    
    if (position < 100) {
        line = " " + line;
    }
    if (position < 10) {
        line = " " + line;
    }
    
    line = (isYou ? "*" : " ") + line;
            
    string name = stat.name;
    int padding = 32 - name.Length();
    for (int p = 0; p < padding; p++) {
        name += " ";
    }
    line += name;
    
    string count = stat.soundCount;
    padding = 7 - count.Length();
    for (int p = 0; p < padding; p++) {
        count += " ";
    }
    line += count;
    
    line += "STEAM_0:" + stat.steamid;
    
    g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, line + "\n");
}

void showSoundStats_singleSound(CBasePlayer@ plr, string chatTrigger) {
    chatTrigger = chatTrigger.ToLowercase();
    const int limit = 20;
    string steamid = g_EngineFuncs.GetPlayerAuthId( plr.edict() );
    steamid = steamid.SubString(8);
    
    SoundStat@ stat = null;
    for (uint i = 0; i < g_stats.size(); i++) {
        if (!g_stats[i].isValid) {
            continue; // chat sound not loaded
        }
        if (g_stats[i].chatTrigger.ToLowercase() == chatTrigger) {
            @stat = @g_stats[i];
            break;
        }
    }
    
    if (stat is null or stat.users.size() == 0) {
        g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "No stats found for " + chatTrigger);
        return;
    }
    
    g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\nTop " + limit + " users of \"" + stat.chatTrigger + "\"\n");
    g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\n      Name                            Uses   Steam ID");
    g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\n-----------------------------------------------------------------\n");
    
    if (stat.users.size() > 0) {
        stat.users.sort(function(a,b) { return a.soundCount > b.soundCount; });
    }

    int yourPosition = -1;
    UserStat@ yourStat = null;
    for (uint k = 0; k < stat.users.size(); k++) {
    
        bool isYou = stat.users[k].steamid == steamid;
        if (isYou) {
            yourPosition = k;
            @yourStat = @stat.users[k];
        }
        
        if (k < limit) {
            printUserStat(plr, k, stat.users[k], isYou);
        }
    }
    
    if (yourPosition > limit) {
        g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "  ...\n");
        printUserStat(plr, yourPosition, yourStat, true);
    }
    
    g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "-----------------------------------------------------------------\n\n");
    g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "Total users: " + stat.users.size() + "\n");
    g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "Total uses:  " + stat.totalUses + "\n\n");
}

void cs_stats(const CCommand@ pArgs) {
    CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
    showSoundStats(plr, pArgs.Arg(1));
}

void writecsstats_cmd(const CCommand@ pArgs) {
    CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
    writeUsageStats();
    g_PlayerFuncs.SayText(plr, "[ChatSounds] Wrote usage stats to " + soundStatsFile + "\n");
}
