/**
 * L4D2 Tank Rock Lag Compensation.
 *
 * -------
 * Credits
 * -------
 * 
 * Author: Luckylock
 */

#include <sourcemod>
#include <sdktools>

#define DEBUG 0
#define MAX_STR_LEN 100
#define SERVER_TICKRATE 100
#define LAG_COMP_ENABLED GetConVarInt(cvarRockTankLagComp)

new Handle:cvarRockTankLagComp;

/**
 * Block 0: Entity Index
 * Block 1: Array of x,y,z rock positions history where: 
 * (frame number) % SERVER_TICKRATE == (array index)
 */
new ArrayList:rockEntitiesArray;

public Plugin myinfo =
{
	name = "L4D2 Tank Rock Lag Compensation",
	author = "Luckylock",
	description = "Provides lag compensation for tank rock entities",
	version = "0.1",
	url = "https://github.com/LuckyServ/"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_ray", ProcessRockHitboxes, "Destroy rock (lag compensated)");
    CreateConVar("sm_rock_tank_lagcomp_enabled", "1", "Toggle for lag compensation", FCVAR_NONE, true, 0.0, true, 1.0);

    cvarRockTankLagComp = FindConVar("sm_rock_tank_lagcomp_enabled"); 
    rockEntitiesArray = CreateArray(2);
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (IsRock(entity)) {
#if DEBUG
        PrintEntityLocation(entity);
#endif
        Array_AddNewRock(rockEntitiesArray, entity);
    }
}

public void OnEntityDestroyed(int entity)
{
#if DEBUG
    PrintEntityLocation(entity);
#endif
    Array_RemoveRock(rockEntitiesArray, entity);
}

public void OnGameFrame()
{
    new Float:pos[3];
    new entity;
    new index = GetGameTickCount() % SERVER_TICKRATE; 
    
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
    array.Set(index, CreateArray(3, SERVER_TICKRATE), 1);
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

public Action ProcessRockHitboxes(int client, int args)
{
    new Float:eyeAng[3];
    new Float:eyePos[3];

    // Rollback rock position
    new Float:lagTime = GetClientLatency(client, NetFlow_Both); /* Should add lerp as well */
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
    new Float:radius = 30.0;
    new Float:c[3];

    new ArrayList:rockPositionsArray;
    new entity;
    new index = rollBackTick % 100;

    PrintToChatAll("%d - %d = %d", GetGameTickCount(), rollBackTick, GetGameTickCount() - rollBackTick);

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
            CTankRock__Detonate(EntRefToEntIndex(entity));
        }
    }

    return Plugin_Handled;
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
