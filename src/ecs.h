#ifndef SOLIS_ECS
#define SOLIS_ECS

typedef struct World World;
typedef Entity long long;

World *world_init();
void world_init(World*);

Entity world_create_entity(World*);

#endif // !SOLIS_ECS
