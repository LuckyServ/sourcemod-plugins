/**
 * ===============================
 * L4D2 Tank Rock Lag Compensation
 * ===============================
 * 
 * This plugin provides lag compensation as well as cvars for weapon 
 * damage & range values on tank rocks.
 * 
 * -------------------------------
 * Lag compensation for tank rocks
 * -------------------------------
 * 
 * The lag compensation is done by keeping track of the position vector history
 * of the tank rock(s) for each previous n frames (defined by MAX_HISTORY_FRAMES). 
 * When a survivor fires his weapon, the client frame is calculated by this formula:
 * 
 * Command Execution Time = Current Server Time - Packet Latency - Client View Interpolation
 *
 * Once the frame number that the client is running at is known, the plugin
 * draws an abstract sphere about the size of the rock at the origin vector
 * of the rock at client frame time. A line-sphere intersection is then calculated 
 * to detect collision. At that point, the weapon damages and ranges come into play.
 *
 * -------------
 * Weapon Damage
 * -------------
 *
 * For a given weapon damage, the damage is equal to the range at which one bullet
 * will kill the rock. For example, a damage of 200 for a gun will kill a rock
 * in one bullet at or below the range of 200 units. Damage is scaled based on
 * distance with this formula:
 *
 * Final Damage = Damage / Distance
 *
 * ------------
 * Weapon Range
 * ------------
 *
 * The weapon range is set to prevent all damages above a certain range. For
 * example, a range of 2000 on a gun category will mean that this type of gun
 * will do no damage to the rock above 2000 units.
 *
 * -------
 * Credits
 * -------
 * 
 * Author: Luckylock
 *
 * Testers & Feedback: Adam, Impulse, Ohzy, Presto, Elk
 */


#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define DEBUG 0
#define MAX_STR_LEN 100
#define MAX_HISTORY_FRAMES 100
#define LAG_COMP_ENABLED GetConVarInt(cvarRockTankLagComp)
#define ROCK_HITBOX_ENABLED GetConVarInt(cvarRockHitbox)
#define SPHERE_HITBOX_RADIUS float(30)
#define ROCK_HEALTH GetConVarFloat(cvarRockHealth)

#define DAMAGE_MAX_ALL_ float(10000)
#define DAMAGE_PISTOL GetConVarFloat(cvarDamagePistol)
#define DAMAGE_MAGNUM GetConVarFloat(cvarDamageMagnum)
#define DAMAGE_SHOTGUN GetConVarFloat(cvarDamageShotgun)
#define DAMAGE_SMG GetConVarFloat(cvarDamageSmg)
#define DAMAGE_RIFLE GetConVarFloat(cvarDamageRifle)
#define DAMAGE_MELEE GetConVarFloat(cvarDamageMelee)
#define DAMAGE_SNIPER GetConVarFloat(cvarDamageSniper)

#define RANGE_MAX_ALL_ float(10000)
#define RANGE_MAX_ALL GetConVarFloat(cvarRangeMaxAll)
#define RANGE_MIN_ALL GetConVarFloat(cvarRangeMinAll)
#define RANGE_PISTOL GetConVarFloat(cvarRangePistol)
#define RANGE_MAGNUM GetConVarFloat(cvarRangeMagnum)
#define RANGE_SHOTGUN GetConVarFloat(cvarRangeShotgun)
#define RANGE_SMG GetConVarFloat(cvarRangeSmg)
#define RANGE_RIFLE GetConVarFloat(cvarRangeRifle)
#define RANGE_MELEE GetConVarFloat(cvarRangeMelee)
#define RANGE_SNIPER GetConVarFloat(cvarRangeSniper)

new ConVar:cvarRockHitbox;
new ConVar:cvarRockTankLagComp;
new ConVar:cvarRockHealth;

new ConVar:cvarDamagePistol;
new ConVar:cvarDamageMagnum;
new ConVar:cvarDamageShotgun;
new ConVar:cvarDamageSmg;
new ConVar:cvarDamageRifle;
new ConVar:cvarDamageMelee;
new ConVar:cvarDamageSniper;

new ConVar:cvarRangeMinAll;
new ConVar:cvarRangeMaxAll;
new ConVar:cvarRangePistol;
new ConVar:cvarRangeMagnum;
new ConVar:cvarRangeShotgun;
new ConVar:cvarRangeSmg;
new ConVar:cvarRangeRifle;
new ConVar:cvarRangeMelee;
new ConVar:cvarRangeSniper;

/**
 * Block 0: Entity Index
 * Block 1: Array of x,y,z rock positions history where: 
 * (frame number) % MAX_HISTORY_FRAMES == (array index)
 * Block 2: Rock Health
 */
new ArrayList:rockEntitiesArray;

public Plugin myinfo =
{
	name = "L4D2 Tank Rock Lag Compensation",
	author = "Luckylock",
	description = "Provides lag compensation for tank rock entities",
	version = "1.0",
	url = "https://github.com/LuckyServ/"
};

// TODO: Incap dmg values, Godframes, Melee Swing delay
public void OnPluginStart()
{
    CreateConVar("sm_rock_hitbox", "1", "Toggle for rock custom hitbox damage", FCVAR_NONE, true, 0.0, true, 1.0);
    CreateConVar("sm_rock_lagcomp", "1", "Toggle for lag compensation", FCVAR_NONE, true, 0.0, true, 1.0);
    CreateConVar("sm_rock_health", "1", "Toggle for lag compensation", FCVAR_NONE, true, 0.0, true, 1.0);

    CreateConVar("sm_rock_damage_pistol", "150", "Gun category damage", FCVAR_NONE, true, 0.0, true, DAMAGE_MAX_ALL_);
    CreateConVar("sm_rock_damage_magnum", "1000", "Gun category damage", FCVAR_NONE, true, 0.0, true, DAMAGE_MAX_ALL_);
    CreateConVar("sm_rock_damage_shotgun", "600", "Gun category damage", FCVAR_NONE, true, 0.0, true, DAMAGE_MAX_ALL_);
    CreateConVar("sm_rock_damage_smg", "75", "Gun category damage", FCVAR_NONE, true, 0.0, true, DAMAGE_MAX_ALL_);
    CreateConVar("sm_rock_damage_rifle", "200", "Gun category damage", FCVAR_NONE, true, 0.0, true, DAMAGE_MAX_ALL_);
    CreateConVar("sm_rock_damage_melee", "1000", "Gun category damage", FCVAR_NONE, true, 0.0, true, DAMAGE_MAX_ALL_);
    CreateConVar("sm_rock_damage_sniper", "10000", "Gun category damage", FCVAR_NONE, true, 0.0, true, DAMAGE_MAX_ALL_);

    CreateConVar("sm_rock_range_min_all", "1", "Gun category range", FCVAR_NONE, true, 0.0, true, RANGE_MAX_ALL_);
    CreateConVar("sm_rock_range_max_all", "2000", "Gun category range", FCVAR_NONE, true, 0.0, true, RANGE_MAX_ALL_);
    CreateConVar("sm_rock_range_pistol", "2000", "Gun category range", FCVAR_NONE, true, 0.0, true, RANGE_MAX_ALL_);
    CreateConVar("sm_rock_range_magnum", "2000", "Gun category range", FCVAR_NONE, true, 0.0, true, RANGE_MAX_ALL_);
    CreateConVar("sm_rock_range_shotgun", "1000", "Gun category range", FCVAR_NONE, true, 0.0, true, RANGE_MAX_ALL_);
    CreateConVar("sm_rock_range_smg", "2000", "Gun category range", FCVAR_NONE, true, 0.0, true, RANGE_MAX_ALL_);
    CreateConVar("sm_rock_range_rifle", "2000", "Gun category range", FCVAR_NONE, true, 0.0, true, RANGE_MAX_ALL_);
    CreateConVar("sm_rock_range_melee", "200", "Gun category range", FCVAR_NONE, true, 0.0, true, RANGE_MAX_ALL_);
    CreateConVar("sm_rock_range_sniper", "10000", "Gun category range", FCVAR_NONE, true, 0.0, true, RANGE_MAX_ALL_);

    cvarRockHitbox = FindConVar("sm_rock_hitbox");
    cvarRockTankLagComp = FindConVar("sm_rock_lagcomp"); 
    cvarRockHealth = FindConVar("sm_rock_health");

    cvarDamagePistol = FindConVar("sm_rock_damage_pistol");
    cvarDamageMagnum = FindConVar("sm_rock_damage_magnum");
    cvarDamageShotgun = FindConVar("sm_rock_damage_shotgun");
    cvarDamageSmg = FindConVar("sm_rock_damage_smg");
    cvarDamageRifle = FindConVar("sm_rock_damage_rifle");
    cvarDamageMelee = FindConVar("sm_rock_damage_melee");
    cvarDamageSniper = FindConVar("sm_rock_damage_sniper");

    cvarRangeMinAll = FindConVar("sm_rock_range_min_all");
    cvarRangeMaxAll = FindConVar("sm_rock_range_max_all");
    cvarRangePistol = FindConVar("sm_rock_range_pistol");
    cvarRangeMagnum = FindConVar("sm_rock_range_magnum");
    cvarRangeShotgun = FindConVar("sm_rock_range_shotgun");
    cvarRangeSmg = FindConVar("sm_rock_range_smg");
    cvarRangeRifle = FindConVar("sm_rock_range_rifle");
    cvarRangeMelee = FindConVar("sm_rock_range_melee");
    cvarRangeSniper = FindConVar("sm_rock_range_sniper");

    rockEntitiesArray = CreateArray(3);
    HookEvent("weapon_fire", ProcessRockHitboxes);
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (IsRock(entity)) {
#if DEBUG
        PrintEntityLocation(entity);
#endif
        Array_AddNewRock(rockEntitiesArray, entity);
        SDKHook(entity, SDKHook_OnTakeDamage, PreventDamage);
    }
}

public void OnEntityDestroyed(int entity)
{
#if DEBUG
    PrintEntityLocation(entity);
#endif
    Array_RemoveRock(rockEntitiesArray, entity);
}

public Action PreventDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype) {
    if (ROCK_HITBOX_ENABLED) {
        damage = 0.0;
        return Plugin_Handled;
    }
    return Plugin_Continue;
}

public void OnGameFrame()
{
    new Float:pos[3];
    new entity;
    new index = GetGameTickCount() % MAX_HISTORY_FRAMES; 
    
    for (int i = 0; i < rockEntitiesArray.Length; ++i) {
        entity = rockEntitiesArray.Get(i,0); 
        GetEntPropVector(EntRefToEntIndex(entity), Prop_Send, "m_vecOrigin", pos); 
        new ArrayList:posArray = rockEntitiesArray.Get(i,1);
        posArray.Set(index, pos[0], 0);
        posArray.Set(index, pos[1], 1);
        posArray.Set(index, pos[2], 2);
    }
}

/**
 * Array Methods
 */

/**
 * Adds a new rock to the array.
 *
 * @param array array of rocks
 * @param entity entity index of the rock
 */
public void Array_AddNewRock(ArrayList array, int entity)
{
    new index = array.Push(EntIndexToEntRef(entity));
    array.Set(index, CreateArray(3, MAX_HISTORY_FRAMES), 1);
    array.Set(index, 0.0, 2);
}

/**
 * Remove a rock from the array.
 *
 * @param array array of rocks
 * @param entity entity index of the rock
 */
public void Array_RemoveRock(ArrayList array, int entity)
{
    new index = Array_SearchRock(array, entity);
    if (index >= 0) {
        new ArrayList:rockPos = array.Get(index, 1);
        rockPos.Clear();
        CloseHandle(rockPos)
        RemoveFromArray(array, index); 
    }
}


/**
 * Searches a rock in the array.
 *
 * @param array array of rocks
 * @param entity entity index to search for
 * @return array index if found, -1 if not found.
 */
public int Array_SearchRock(ArrayList array, entity)
{
    new rockEntity;
    entity = EntIndexToEntRef(entity);

    for (int i = 0; i < array.Length; ++i) {
        rockEntity = array.Get(i, 0);
        if (rockEntity == entity) {
            return i;
        } 
    }

    return -1;
}

/**
 * Ray Methods
 */

public Action ProcessRockHitboxes(Event event, const char[] name, 
    bool dontBroadcast)
{
    if (rockEntitiesArray.Length == 0) {
        return Plugin_Handled;
    }

    new client = GetClientOfUserId(event.GetInt("userid"));

    new Float:eyeAng[3];
    new Float:eyePos[3];

    // Rollback rock position
    new String:buffer[MAX_STR_LEN];
    GetClientInfo(client, "cl_interp", buffer, MAX_STR_LEN);
    new Float:clientLerp = StringToFloat(buffer);
    new Float:lagTime = GetClientLatency(client, NetFlow_Both) + clientLerp;
    new rollBackTick = LAG_COMP_ENABLED ? 
        GetGameTickCount() - RoundToNearest(lagTime / GetTickInterval()) : GetGameTickCount();

    GetClientEyeAngles(client, eyeAng);
    GetClientEyePosition(client, eyePos);

    // Abstract sphere hitbox implementation
    // https://en.wikipedia.org/wiki/Line%E2%80%93sphere_intersection

    // Get unit vector l
    new Float:l[3];
    GetAngleVectors(eyeAng, l, NULL_VECTOR, NULL_VECTOR);

    // Get origin of line o
    new Float:o[3];
    o[0] = eyePos[0];
    o[1] = eyePos[1];
    o[2] = eyePos[2];
    new Float:o_Minus_c[3];

    // Sphere vectors
    new Float:radius = SPHERE_HITBOX_RADIUS;
    new Float:c[3];

    new ArrayList:rockPositionsArray;
    new entity;
    new index = rollBackTick % MAX_HISTORY_FRAMES;

    //PrintToChatAll("%d - %d = %d", GetGameTickCount(), rollBackTick, GetGameTickCount() - rollBackTick);

    for (int i = 0; i < rockEntitiesArray.Length; ++i) {

        entity = rockEntitiesArray.Get(i,0); 
        rockPositionsArray = rockEntitiesArray.Get(i,1);

        c[0] = rockPositionsArray.Get(index, 0);
        c[1] = rockPositionsArray.Get(index, 1);
        c[2] = rockPositionsArray.Get(index, 2);
        SubtractVectors(o,c,o_Minus_c);

        new Float:delta = GetVectorDotProduct(l, o_Minus_c) * GetVectorDotProduct(l, o_Minus_c) 
            - GetVectorLength(o_Minus_c, true) + radius*radius;

        if (delta >= 0.0) {
            ApplyDamageOnRock(i, client, eyePos, c, event, entity);
        }
    }

    return Plugin_Handled;
}

public void ApplyDamageOnRock(rockIndex, client, float[3] eyePos, float[3] c, Event event,
rockEntity)
{
    new String:weaponName[MAX_STR_LEN]; 
    event.GetString("weapon", weaponName, MAX_STR_LEN);
    new Float:range = GetVectorDistance(eyePos, c);

    //PrintToChatAll("Weapon: %s | Range: %.2f", weaponName, range);

    if ((!ROCK_HITBOX_ENABLED) || range > RANGE_MAX_ALL || (range < RANGE_MIN_ALL && !IsMelee(weaponName))) {
        return;

    } else if (IsSmg(weaponName)) {
        if (range > RANGE_SMG) return;
        ApplyBulletToRock(rockIndex, rockEntity, DAMAGE_SMG, range);
        
    } else if (IsPistol(weaponName)) {
        if (range > RANGE_PISTOL) return;
        ApplyBulletToRock(rockIndex, rockEntity, DAMAGE_PISTOL, range);

    } else if (IsMagnum(weaponName)) {
        if (range > RANGE_MAGNUM) return;
        ApplyBulletToRock(rockIndex, rockEntity, DAMAGE_MAGNUM, range);

    } else if (IsShotgun(weaponName)) {
        if (range > RANGE_SHOTGUN) return;
        ApplyBulletToRock(rockIndex, rockEntity, DAMAGE_SHOTGUN, range);

    } else if (IsRifle(weaponName)) {
        if (range > RANGE_RIFLE) return;
        ApplyBulletToRock(rockIndex, rockEntity, DAMAGE_RIFLE, range);

    } else if (IsMelee(weaponName)) {
        if (range > RANGE_MELEE) return;
        ApplyBulletToRock(rockIndex, rockEntity, DAMAGE_MELEE, range);

    } else if (IsSniper(weaponName)) {
        if (range > RANGE_SNIPER) return;
        ApplyBulletToRock(rockIndex, rockEntity, DAMAGE_SNIPER, range);
    }
    
}

public void ApplyBulletToRock(rockIndex, rockEntity, float damage, float range)
{
    new Float:rockDamage = rockEntitiesArray.Get(rockIndex, 2);
    rockDamage += damage / range;

    //PrintToChatAll("Rock health: %.2f", ROCK_HEALTH - rockDamage);

    if (rockDamage >= ROCK_HEALTH) {
        CTankRock__Detonate(rockEntity);
    } else {
        rockEntitiesArray.Set(rockIndex, rockDamage, 2);
    }
}

public bool IsPistol(const char[] weaponName)
{
    return StrEqual(weaponName, "pistol");
}

public bool IsMagnum(const char[] weaponName)
{
    return StrEqual("pistol_magnum", weaponName);
}

public bool IsShotgun(const char[] weaponName)
{
    return StrEqual(weaponName, "shotgun_chrome")
        || StrEqual(weaponName, "shotgun_spas")
        || StrEqual(weaponName, "autoshotgun")
        || StrEqual(weaponName, "pumpshotgun");
}

public bool IsSmg(const char[] weaponName)
{
    return StrEqual(weaponName, "smg")
        || StrEqual(weaponName, "smg_silenced")
        || StrEqual(weaponName, "smg_mp5");
}

public bool IsRifle(const char[] weaponName)
{
    return StrEqual(weaponName, "rifle")
        || StrEqual(weaponName, "rifle_ak47")
        || StrEqual(weaponName, "rifle_desert")
        || StrEqual(weaponName, "rifle_m60")
        || StrEqual(weaponName, "rifle_sg552");
}

public bool IsMelee(const char[] weaponName)
{
    return StrEqual(weaponName, "chainsaw")
        || StrEqual(weaponName, "melee");
}

public bool IsSniper(const char[] weaponName)
{
    return StrEqual(weaponName, "sniper_awp")
        || StrEqual(weaponName, "sniper_military")
        || StrEqual(weaponName, "sniper_scout");
}

/**
 * Print Methods
 */

public void PrintEntityLocation(int entity)
{
    if (IsValidEntity(entity)) {
        new String:classname[MAX_STR_LEN];
        new Float:position[3];
        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", position);
        GetEntityClassname(entity, classname, MAX_STR_LEN);
        PrintToChatAll("Entity %s (%d) is at location: (%.2f, %.2f, %.2f)",
            classname, EntIndexToEntRef(entity), position[0], position[1], position[2]);
    }
}

public bool IsRock(int entity)
{
    if (IsValidEntity(entity)) {
        new String:classname[MAX_STR_LEN];
        GetEntityClassname(entity, classname, MAX_STR_LEN);
        return StrEqual(classname, "tank_rock");
    }
    return false;
}

// Credits to Visor
CTankRock__Detonate(rock)
{
    static Handle:call = INVALID_HANDLE;
    if (call == INVALID_HANDLE)
    {
        StartPrepSDKCall(SDKCall_Entity);
        if (!PrepSDKCall_SetSignature(SDKLibrary_Server, "@_ZN9CTankRock8DetonateEv", 0))
        {
            return;
        }
        call = EndPrepSDKCall();
        if (call == INVALID_HANDLE)
        {
            return;
        }
    }
    SDKCall(call, rock);
}

/**
 * Vector functions
 */

public void Vector_Print(float[3] v)
{
    PrintToChatAll("(%.2f, %.2f, %.2f)", v[0],v[1],v[2]);
}
