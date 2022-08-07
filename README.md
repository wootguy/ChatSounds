# ChatSounds
Modified version of [incognico's ChatSounds plugin](https://github.com/incognico/svencoop-plugins/blob/master/twlz/ChatSounds.as).

## New stuff  
`.csstats [sound]` = show how many times each sound was used.  
`.csvol [0-100]` = adjust volume of chatsounds.  
`.csmute [player name/id]` = mute a player's chatsounds.  
`say "sound [0-255]"` = play pitched sound without using `.cspitch`  
`.csload/.cslist/.cs/.csmic/.listsounds2` = Commands for loading/unloading/streaming sounds. Add thousands of sounds without impacting load times for players! Sounds are streamed over microphone audio when not loaded. Players can choose up to 8 sounds to load as normal chat sounds. Because `.csmic` is global and loud, it is disabled by default and every player must opt into it.  
`.csreliable` = stream `.csmic` sounds using the reliable channel. This will fix glitches or gaps in audio if you have packet loss, but may cause desyncs or the "reliable channel overflow" error.

## Setup

1) Create a `ChatSounds` folder in your `plugins` folder and copy all the scripts into it.
2) Add this to default_plugins.txt
```
	"plugin"
	{
		"name" "ChatSounds"
		"script" "ChatSounds/ChatSounds"
	}
```

### Config

The config file (`scripts/plugins/cfg/ChatSounds.txt`) is the same as in incognico's version with an added `[extra_sounds]` section where you can place sounds that are normally unloaded. Extra sounds can be streamed with `.csmic`, previewed with `.cs`, or converted to normal sounds using `.csload`. Sounds are loaded on map change.
Example ChatSounds.txt config:
```
bleh twlz/bleh.wav
wellshit twlz/wellshit.wav

// the sounds listed below this [extra_sounds] line must be loaded with .csload or streamed with .csmic
[extra_sounds]
amogoos twlz/stolen/amogoos.wav
amogugus twlz/stolen/amogugus.wav
```

### Sound streaming

For sound streaming to work (`.cs` and `.csmic`) you need to build the steam_voice program from the [Radio plugin](https://github.com/wootguy/Radio) and run it using these arguments:  
`steam_voice.exe "chatsounds" <path_to_micsound_file> <path_to_chatsound_txt> <path_to_Sven_Coop_folder>`

Example Linux script to start the program:  
```
steam_voice \
	chatsounds \
	my_sven_install/svencoop/scripts/plugins/store/_tocs.txt \
	my_sven_install/svencoop_addon/scripts/plugins/cfg/ChatSounds.txt \
	my_sven_install
```

The program must be running at all times. It will auto-reload sounds as you update the ChatSounds.txt, on map change. All sound files must be .wav format.

The micsound file (_tocs.txt) is written to by the angelscript plugin. It sends commands which steam_voice reads, then steam_voice converts the .wav files into .spk files which the plugin can use to send audio packets to players.


### Speeding up load times for players
Ever join a server, load into the map, and then the game freezes for a while? That happens because sounds are being decompressed and loaded into memory. That will happen on every map load if you use a plugin like this. Servers often use .ogg files for chat sounds which is the slowest format to decode.

I think this format is a good balance of quality, loading time, and file size:  
`8-bit uncompressed WAV, mono, 22khz or less`   
For really long files like music, IMA ADPCM compresses well and loads much faster than ogg/mp3.

To demonstrate, here are my load times when precaching 3000 chat sound files (4 second length, 48khz, mono):
```
AUDIO FORMAT         FIRST LOAD TIME     SECOND LOAD TIME
---------------------------------------------------------
OGG (Q10)              39 seconds          23 seconds
OGG (Q0)               26 seconds          12 seconds
MP3 (medium)           27 seconds          13 seconds
WAV (IMA ADPCM)        18 seconds          7 seconds
WAV (IMA ADPCM, 22khz) 18 seconds          4 seconds
WAV (32bit float)      26 seconds          3 seconds
WAV (8bit, 22khz)      13 seconds          2 seconds
WAV (8bit, 8khz)       13 seconds          1 second
```

You can see that the .wav files load up to 20x faster than OGG/MP3.

I don't know why the first load time is so much longer than the second load. I guess because my hdd or sven is caching the files. I've also got an SSD and a 4.5 GHz CPU so loading times are probably much faster for me than average.

Windows Defender will cause load times to double due to some bug with it closing files. The following is a solution to that, copied from incognico in the TWLZ discord:
> ⚠️ Windows users: Exclude the Sven Co-op folder from Windows Defender (Settings -> Update & Security -> Windows Security -> Virus & threat Protection -> Virus & threat Protection settings -> Manage Settings -> Exclusions (at the bottom) -> Add or remove exclusions -> + Add an exclusion -> Folder -> C:\Program Files (x86)\Steam\steamapps\common\Sven Co-op)
> 
> (If you are doubtful, see https://www.youtube.com/watch?v=HuTxA25oHBg for a comparison video. The Defender problem is explained in https://gregoryszorc.com/blog/2021/04/06/surprisingly-slow (paragraph "Closing File Handles on Windows") The issue was also reported to the Sven Co-op team, but as long as no fix is in place, manual action is required.)
