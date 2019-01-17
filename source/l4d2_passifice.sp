#define MAX_BUFFER 200
#define MAP_NAME_SWITCH "c6m2_bedlam"
#define MAP_NAME_NEXT "c7m1_docks"

public Plugin myinfo =
{
	name = "L4D2 Passifice",
	author = "Luckylock",
	description = "Combines The Passing and The Sacrifice in one map",
	version = "1.0",
	url = "https://github.com/LuckyServ/"
};

public void OnMapStart() 
{
    new String:mapName[MAX_BUFFER]; 
    GetCurrentMap(mapName, MAX_BUFFER);

    if (StrEqual(mapName, MAP_NAME_SWITCH, false)) {
        SetNextMap(MAP_NAME_NEXT);
    }
}
