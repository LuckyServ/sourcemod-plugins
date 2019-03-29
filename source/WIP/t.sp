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
 * Block 1: Array of x,y,z positions where: 
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
    RegConsoleCmd("sm_ray", Cmd_DrawRay, "Destroy rock (lag compensated)");
    rockEntitiesArray = CreateArray(2);
    CreateConVar("sm_rock_tank_lagcomp_enabled", "1", "Toggle for lag compensation", FCVAR_NONE, true, 0.0, true, 1.0);

    cvarRockTankLagComp = FindConVar("sm_rock_tank_lagcomp_enabled"); 
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

public void Array_AddNewRock(ArrayList array, int entity)
{
    new index = array.Push(EntIndexToEntRef(entity));
    array.Set(index, CreateArray(3, SERVER_TICKRATE), 1);
}

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

public Action Cmd_DrawRay(int client, int args)
{
    new Float:eyeAng[3];
    new Float:eyePos[3];
    new Float:hitPosition[3];


    // Rollback rock position
    new Float:lagTime = GetClientLatency(client, NetFlow_Both); /* Should add lerp as well */
    new rollBackTick = GetGameTickCount() - RoundToNearest(lagTime / GetTickInterval());


    if (LAG_COMP_ENABLED) {
        PrintToChatAll("%d - %d = %d", GetGameTickCount(), rollBackTick,
            GetGameTickCount() - rollBackTick);
        // Move rock(s) back in time
        Array_MoveRocks(rockEntitiesArray, rollBackTick % 100);
    }

    GetClientEyeAngles(client, eyeAng);
    GetClientEyePosition(client, eyePos);

    new Handle:ray = TR_TraceRayFilterEx(eyePos, eyeAng, MASK_SHOT, 
        RayType_Infinite, Trace_FilterSelf, client); 

    if (TR_DidHit(ray)) {
        TR_GetEndPosition(hitPosition, ray);
#if DEBUG
        PrintEntityLocation(TR_GetEntityIndex(ray));
#endif
        DestroyRock(TR_GetEntityIndex(ray));
    }

    CloseHandle(ray);

    // Move rock(s) back to current frame
    Array_MoveRocks(rockEntitiesArray, GetGameTickCount() % 100);

    return Plugin_Continue;
}

public bool: Trace_FilterSelf(entity, mask, any:data) {
    return entity != data;
}

public void Array_MoveRocks(ArrayList array, tick)
{
    new ArrayList:rockPos;
    new Float:pos[3];
    new entity;

    for (int i = 0; i < array.Length; ++i)
    {
        entity = array.Get(i,0);
        rockPos = array.Get(i,1);
        pos[0] = rockPos.Get(tick,0);
        pos[1] = rockPos.Get(tick,1);
        pos[2] = rockPos.Get(tick,2);
        SetEntPropVector(EntRefToEntIndex(entity), Prop_Send, "m_vecOrigin", pos);
    }
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

public void DestroyRock(int entity)
{
    if (IsRock(entity)) {
        RemoveEdict(entity);
    }
}
