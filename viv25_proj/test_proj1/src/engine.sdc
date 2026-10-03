# Standalone Phase F engine experiment: direct 27 MHz clock.
# Top module: gqh_update_engine. No board pin constraints are included.
create_clock -name engine_clock -period 37.037037 [get_ports {clock}]
