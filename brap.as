class Brap {
	EHandle h_sprite;
	EHandle h_model;
	float expire_time; // time brap should be deleted if inactive
	
	Brap(EHandle h_sprite, EHandle h_model) {
		this.h_sprite = h_sprite;
		this.h_model = h_model;
		expire_time = g_Engine.time + BRAP_LIFE;
	}
	
	Brap() {}
}

array<Brap> g_braps;
array<float> g_sniffers(g_Engine.maxClients+1); // value = time sniff will end

array<string> brap_sprites = {
	"sprites/sence/cloud1.spr",
	"sprites/sence/cloud2.spr",
	"sprites/sence/cloud3.spr",
	"sprites/sence/cloud4.spr"
};
const string cycler_model = "models/scmod/null.mdl";
const float SNIFF_DISTANCE = 256;
const float BRAP_SPR_SCALE = 0.2f; // sprite scale at maximum size
const float INHALE_DIST = 96.0f; // distance that sniffing affects braps
const float KILL_DIST = 8.0f; // braps are killed within this range
const float BRAP_LIFE = 20.0f; // braps live for this long before being deleted
const float BRAP_RENDER_AMT = 24.0f;
const float BRAP_SPREAD_DIST = 16.0f; // braps will push each other away within this dist

void te_bubbles(Vector mins, Vector maxs, float height=256.0f, 
	string sprite="sprites/bubble.spr", uint8 count=64, float speed=16.0f,
	NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null)
{
	NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);
	m.WriteByte(TE_BUBBLES);
	m.WriteCoord(mins.x);
	m.WriteCoord(mins.y);
	m.WriteCoord(mins.z);
	m.WriteCoord(maxs.x);
	m.WriteCoord(maxs.y);
	m.WriteCoord(maxs.z);
	m.WriteCoord(height);
	m.WriteShort(g_EngineFuncs.ModelIndex(sprite));
	m.WriteByte(count);
	m.WriteCoord(speed);
	m.End();
}

void te_bloodsprite(Vector pos, string sprite1="sprites/bloodspray.spr",
	string sprite2="sprites/blood.spr", uint8 color=70, uint8 scale=3,
	NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null)
{
	NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);
	m.WriteByte(TE_BLOODSPRITE);
	m.WriteCoord(pos.x);
	m.WriteCoord(pos.y);
	m.WriteCoord(pos.z);
	m.WriteShort(g_EngineFuncs.ModelIndex(sprite1));
	m.WriteShort(g_EngineFuncs.ModelIndex(sprite2));
	m.WriteByte(color);
	m.WriteByte(scale);
	m.End();
}

// multiply a matrix with a vector (assumes w component of vector is 1.0f) 
Vector matMultVector(array<float> rotMat, Vector v)
{
	Vector outv;
	outv.x = rotMat[0]*v.x + rotMat[4]*v.y + rotMat[8]*v.z  + rotMat[12];
	outv.y = rotMat[1]*v.x + rotMat[5]*v.y + rotMat[9]*v.z  + rotMat[13];
	outv.z = rotMat[2]*v.x + rotMat[6]*v.y + rotMat[10]*v.z + rotMat[14];
	return outv;
}

array<float> rotationMatrix(Vector axis, float angle)
{
	axis = axis.Normalize();
    float s = sin(angle);
    float c = cos(angle);
    float oc = 1.0 - c;
 
	array<float> mat = {
		oc * axis.x * axis.x + c,          oc * axis.x * axis.y - axis.z * s, oc * axis.z * axis.x + axis.y * s, 0.0,
		oc * axis.x * axis.y + axis.z * s, oc * axis.y * axis.y + c,          oc * axis.y * axis.z - axis.x * s, 0.0,
		oc * axis.z * axis.x - axis.y * s, oc * axis.y * axis.z + axis.x * s, oc * axis.z * axis.z + c,			 0.0,
		0.0,                               0.0,                               0.0,								 1.0
	};
	return mat;
}

// Randomize the direction of a vector by some amount
// Max degrees = 360, which makes a full sphere
Vector spreadDir(Vector dir, float degrees)
{
	float spread = Math.DegreesToRadians(degrees) * 0.5f;
	float x, y;
	Vector vecAiming = dir;
	
	float c = Math.RandomFloat(0, Math.PI*2); // random point on circle
	float r = Math.RandomFloat(-1, 1); // random radius
	x = cos(c) * r * spread;
	y = sin(c) * r * spread;
	
	// get "up" vector relative to aim direction
	Vector pitAxis = CrossProduct(dir, Vector(0, 0, 1)).Normalize(); // get left vector of aim dir
	Vector yawAxis = CrossProduct(dir, pitAxis).Normalize(); // get up vector relative to aim dir
	
	// Apply rotation around arbitrary "up" axis
	array<float> yawRotMat = rotationMatrix(yawAxis, x);
	vecAiming = matMultVector(yawRotMat, vecAiming).Normalize();
	
	// Apply rotation around "left/right" axis
	array<float> pitRotMat = rotationMatrix(pitAxis, y);
	vecAiming = matMultVector(pitRotMat, vecAiming).Normalize();
			
	return vecAiming;
}

CBaseEntity@ getTootEnt(CBasePlayer@ plr) {
	if (plr.IsAlive() || plr.pev.effects & EF_NODRAW == 0) {
		return plr;
	}
	
	if (plr.GetObserver().IsObserver() && plr.GetObserver().HasCorpse()) {
		CBaseEntity@ ent = null;
		do {
			@ent = g_EntityFuncs.FindEntityByClassname(ent, "deadplayer"); 
			if (ent !is null) {
				CustomKeyvalues@ pCustom = ent.GetCustomKeyvalues();
				CustomKeyvalue ownerKey( pCustom.GetKeyvalue( "$i_hipoly_owner" ) );
				
				if (ownerKey.Exists() && ownerKey.GetInteger() == plr.entindex()) {
					return ent;
				}
			}
		} while (ent !is null);
	}
	
	return null;
}

bool canTootEffect(CBasePlayer@ plr) {
	return plr.IsAlive() || (plr.pev.effects & EF_NODRAW == 0) || (plr.GetObserver().IsObserver() && plr.GetObserver().HasCorpse());
}

void bubble_toot(EHandle h_plr, int power) {
	CBaseEntity@ plr = h_plr;
	if (plr is null) {
		return;
	}
	
	if (plr.pev.waterlevel >= WATERLEVEL_WAIST) {
		Vector pos = plr.pev.origin;
		Vector sz = Vector(8,8,8);
		
		if (!plr.IsAlive()) {
			pos.z -= (35 - sz.z);
		}
		
		float bottomZ = pos.z - sz.z;
		float height = g_Utility.WaterLevel(pos - Vector(0,0,sz.z), bottomZ, bottomZ + 1024);
		te_bubbles(pos - sz, pos + sz, height - bottomZ, "sprites/bubble.spr", power, 16);
	}
}

void cloud_toot(EHandle h_plr, float spread, float baseSpeed, float speedMultMax) {
	CBaseEntity@ plr = h_plr;
	if (plr is null) {
		return;
	}
	
	float speed = baseSpeed * Math.RandomFloat(0.8f, speedMultMax);
	Vector buttPos = plr.pev.origin;
	Vector angles = plr.pev.v_angle;
	angles.x = 0;
	Math.MakeVectors(angles);
	Vector dir = g_Engine.v_forward;
	dir = spreadDir(dir, spread) * -speed;
	
	if (!plr.IsAlive()) {
		buttPos.z -= 35;
		float u = Math.RandomFloat(0, 1);
		float v = Math.RandomFloat(0, 1);
		float theta = 2 * Math.PI * u;
		float phi = acos(2 * v - 1);
		float x = sin(phi) * cos(theta);
		float y = sin(phi) * sin(theta);
		float z = abs(cos(phi));
		dir = Vector(x, y, z)*speed*0.3f;
	}
	
	dictionary keys;
	keys["origin"] = buttPos.ToString();
	keys["velocity"] = dir.ToString();
	keys["model"] = cycler_model;
	CBaseEntity@ brapModel = g_EntityFuncs.CreateEntity("cycler", keys, true);
	brapModel.pev.solid = SOLID_NOT;
	brapModel.pev.movetype = MOVETYPE_FLY;
	brapModel.pev.velocity = dir;
	g_EntityFuncs.SetSize(brapModel.pev, Vector(0,0,0), Vector(0,0,0));
	
	keys["origin"] = buttPos.ToString();
	keys["velocity"] = dir.ToString();
	keys["model"] = brap_sprites[Math.RandomLong(0, brap_sprites.size()-1)];
	keys["rendermode"] = "5";
	keys["renderamt"] = "" + BRAP_RENDER_AMT;
	keys["rendercolor"] = "200 255 200";
	keys["scale"] =  "0.01";
	CBaseEntity@ brapSprite = g_EntityFuncs.CreateEntity("env_sprite", keys, true);
	brapSprite.pev.movetype = MOVETYPE_FOLLOW;
	@brapSprite.pev.aiment = @brapModel.edict();
	
	g_braps.insertLast(Brap(EHandle(brapSprite), EHandle(brapModel)));
}

void shit(EHandle h_plr, int scale) {
	CBaseEntity@ plr = h_plr;
	if (plr is null) {
		return;
	}
	
	Vector buttPos = plr.pev.origin;
	
	if (!plr.IsAlive()) {
		buttPos.z -= 35;
	}
	
	te_bloodsprite(buttPos + g_Engine.v_forward*-4, "sprites/bloodspray.spr", "sprites/blood.spr", 22, scale);
}

void do_brap(CBasePlayer@ plr, string arg, float pitch) {
	
	if (!canTootEffect(plr)) {
		return;
	}
	
	float speed = (100.0f/pitch);
	
	CBaseEntity@ tootEnt = getTootEnt(plr);
	
	if (tootEnt.pev.waterlevel >= WATERLEVEL_WAIST) {		
		if (arg == "brap") {
			g_Scheduler.SetInterval("bubble_toot", 0.05f*speed, 16, EHandle(tootEnt), 4);
			g_Scheduler.SetInterval("shit", 0.05f*speed, 15, EHandle(tootEnt), 8);
		} else if (arg == "braprape") {
			g_Scheduler.SetInterval("bubble_toot", 0.05f*speed, 16, EHandle(tootEnt), 16);
			g_Scheduler.SetInterval("shit", 0.05f*speed, 15, EHandle(tootEnt), 32);
		} else if (arg == "toot") {
			g_Scheduler.SetInterval("bubble_toot", 0.05f*speed, 1, EHandle(tootEnt), 12);
		} else if (arg == "tooot") {
			g_Scheduler.SetInterval("bubble_toot", 0.05f*speed, 1, EHandle(tootEnt), 40);
		} else if (arg == "tootrape") {
			g_Scheduler.SetInterval("bubble_toot", 0.05f*speed, 2, EHandle(tootEnt), 180);
		}
	} else {
		if (arg == "brap") {
			g_Scheduler.SetInterval("cloud_toot", 0.1f*speed, 8, EHandle(tootEnt), 90.0f, 100.0f, 1.5f);
			g_Scheduler.SetInterval("shit", 0.05f*speed, 20, EHandle(tootEnt), 8);
		} else if (arg == "braprape") {
			g_Scheduler.SetInterval("cloud_toot", 0.05f*speed, 15, EHandle(tootEnt), 360.0f, 150.0f, 2.0f);
			g_Scheduler.SetInterval("shit", 0.05f*speed, 15, EHandle(tootEnt), 32);
		} else if (arg == "toot") {
			g_Scheduler.SetInterval("cloud_toot", 0.05f*speed, 1, EHandle(tootEnt), 0, 100.0f, 1.0f);
		} else if (arg == "tooot") {
			for (uint i = 0; i < 10; i++) {
				g_Scheduler.SetInterval("cloud_toot", 0.05f*speed, 1, EHandle(tootEnt), 20.0f, 100.0f, 3.0f);
			}
		} else if (arg == "tootrape") {
			for (uint i = 0; i < 40; i++) {
				g_Scheduler.SetInterval("cloud_toot", 0.05f*speed, 1, EHandle(tootEnt), 20.0f, 200.0f, 8.0f);
			}
		}
	}
}

void do_sniff(CBasePlayer@ plr, string arg, float pitch) {	
	float sniff_time = 1.3f;
	if (arg == "sniff") {
		sniff_time = 1.3f;
	}
	else if (arg == "snifff") {
		sniff_time = 1.0f;
	}
	else if (arg == "sniffrape") {
		sniff_time = 4.0f;
	}
	
	g_sniffers[plr.entindex()] = g_Engine.time + (sniff_time * (100.0f/pitch));
}

void brap_precache() {
	for (uint i = 0; i < brap_sprites.size(); i++) {
		g_Game.PrecacheModel(brap_sprites[i]);
	}
	
	g_Game.PrecacheModel(cycler_model);
	g_sniffers.resize(0);
	g_sniffers.resize(g_Engine.maxClients+1);
}

void brap_think() {
	array<Brap> new_braps;
	
	array<CBaseEntity@> sniffSources;
	for (uint i = 1; i < g_sniffers.size(); i++) {
		if (g_sniffers[i] > g_Engine.time) {
			CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
			
			if (plr !is null) {
				CBaseEntity@ tootEnt = getTootEnt(plr);
				if (tootEnt !is null) {
					sniffSources.insertLast(tootEnt);
				}
			}
		}
	}
	
	for (uint i = 0; i < g_braps.size(); i++) {
		CBaseEntity@ brap = g_braps[i].h_sprite;
		CBaseEntity@ mdl = g_braps[i].h_model;
		
		if (brap is null or mdl is null or g_braps[i].expire_time < g_Engine.time) {
			g_EntityFuncs.Remove(g_braps[i].h_sprite);
			g_EntityFuncs.Remove(g_braps[i].h_model);
			continue;
		}
		
		if (sniffSources.size() > 0) {
			for (uint k = 0; k < sniffSources.size(); k++) {
				CBaseEntity@ sniffer = sniffSources[k];
				bool isDucking = sniffer.pev.flags & FL_DUCKING != 0;
				Vector sniffTarget = sniffer.pev.origin + Vector(0,0, isDucking ? 10 : 26);
				
				if (!sniffer.IsAlive()) {
					sniffTarget.z = sniffer.pev.origin.z - 35;
				}
				
				Vector sniffDelta = sniffTarget - mdl.pev.origin;
				float dist = sniffDelta.Length();
				
				if (dist > SNIFF_DISTANCE) {
					continue;
				}
				
				mdl.pev.velocity = sniffDelta.Normalize() * (SNIFF_DISTANCE - dist)*0.5f;
				
				float targetScale = BRAP_SPR_SCALE;
				if (dist < INHALE_DIST) {
					float newScale = dist != 0 ? (dist / INHALE_DIST) * BRAP_SPR_SCALE : 0.05f;
					targetScale = Math.max(newScale, 0.001f);
				}
				
				if (brap.pev.scale > targetScale*1.2f) {
					brap.pev.scale *= 0.8f;
				} else if (brap.pev.scale < targetScale*0.8f) {
					brap.pev.scale *= 1.2f;
				}
				
				if (dist < KILL_DIST and brap.pev.scale < BRAP_SPR_SCALE*0.1f) {
					sniffer.TakeDamage(mdl.pev, mdl.pev, 1, DMG_NERVEGAS | DMG_SNIPER); // bypass armor
					g_EntityFuncs.Remove(g_braps[i].h_sprite);
					g_EntityFuncs.Remove(g_braps[i].h_model);
					continue;
				}
			}
		} else {
			CBaseEntity@ otherBrap = null;
			do {
				@otherBrap = g_EntityFuncs.FindEntityInSphere(otherBrap, mdl.pev.origin, BRAP_SPREAD_DIST, "cycler", "classname"); 
				if (otherBrap !is null and otherBrap.entindex() != mdl.entindex()) {
					mdl.pev.velocity = mdl.pev.velocity + (mdl.pev.origin - otherBrap.pev.origin)*0.1f;
				}
			} while (otherBrap !is null);
			
			mdl.pev.velocity = mdl.pev.velocity * 0.9f;
			
			if (mdl.pev.velocity.Length() < 1) {
				mdl.pev.velocity = Vector(0,0,0);
			}
			
			if (brap.pev.scale < BRAP_SPR_SCALE) {
				brap.pev.scale *= 1.2f;
				
				if (brap.pev.scale > BRAP_SPR_SCALE) {
					brap.pev.scale = BRAP_SPR_SCALE;
				}
			}
		}	

		float life_left = g_braps[i].expire_time - g_Engine.time;
		
		if (life_left < 3.0f) {
			brap.pev.renderamt = (life_left / 3.0f) * BRAP_RENDER_AMT;
		}
		
		new_braps.insertLast(g_braps[i]);
	}
	
	g_braps = new_braps;
}

void brap_unload() {
	for (uint i = 0; i < g_braps.size(); i++) {
		g_EntityFuncs.Remove(g_braps[i].h_sprite);
		g_EntityFuncs.Remove(g_braps[i].h_model);
	}
}