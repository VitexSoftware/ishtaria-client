shader_type spatial;

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform bool has_heightmap = false;
uniform float planet_radius = 6371.0;
uniform float elevation_scale = 8.0;
uniform sampler2D environment_map : filter_nearest, repeat_disable;
uniform bool has_environment = false;
uniform bool water_pass = false;
uniform bool is_detail = false;
uniform vec3 detail_direction = vec3(0.0);
uniform vec2 wave_phase = vec2(0.0);
varying vec3 surface_point;
varying float detail_elevation;
varying vec3 local_point;

vec2 map_coordinates(vec3 direction, float size) {
		vec3 magnitude = abs(direction);
		float face;
		vec2 point;
		if (magnitude.x >= magnitude.y && magnitude.x >= magnitude.z) {
			face = direction.x >= 0.0 ? 0.0 : 1.0;
			point = vec2(direction.x >= 0.0 ? -direction.z : direction.z, direction.y);
		} else if (magnitude.y >= magnitude.z) {
			face = direction.y >= 0.0 ? 2.0 : 3.0;
			point = vec2(direction.x, direction.y >= 0.0 ? -direction.z : direction.z);
		} else {
			face = direction.z >= 0.0 ? 4.0 : 5.0;
			point = vec2(direction.z >= 0.0 ? direction.x : -direction.x, direction.y);
		}
		vec2 squared = point * point;
		vec2 difference = 2.0 * (squared - squared.yx);
		vec2 coefficient = vec2(3.0) + difference;
		vec2 cube = sign(point) * sqrt(max(0.5 * (coefficient - sqrt(max(coefficient * coefficient - 24.0 * squared, vec2(0.0)))), vec2(0.0)));
		vec2 pixel = vec2((cube.x + 1.0) * 0.5, (1.0 - cube.y) * 0.5);
		pixel = clamp(pixel * size, vec2(0.5), vec2(size - 0.5));
		return vec2((face * size + pixel.x) / (6.0 * size), pixel.y / size);
	}

float sample_height(vec3 direction) {
	return texture(heightmap, map_coordinates(direction, float(textureSize(heightmap, 0).y))).r;
}

vec2 sample_environment(vec3 direction) {
	return texture(environment_map, map_coordinates(direction, float(textureSize(environment_map, 0).y))).rg;
}

void vertex() {
	surface_point = normalize(is_detail ? NORMAL : VERTEX);
	detail_elevation = UV2.x;
	local_point = VERTEX;
	if (has_heightmap && !is_detail) {
		float elevation = (sample_height(surface_point) * 2.0 - 1.0) * elevation_scale;
		if (water_pass) {
			elevation = has_environment ? (sample_environment(surface_point).r * 2.0 - 1.0) * elevation_scale : 0.0;
			elevation += 0.001;
		}
		VERTEX = surface_point * (planet_radius + elevation);
	}
}

void fragment() {
	ALBEDO = vec3(0.22, 0.45, 0.28);
	ROUGHNESS = 1.0;
	if (has_heightmap) {
		vec3 direction = normalize(surface_point);
		if (!is_detail && length(detail_direction) > 0.5 && length(direction - detail_direction) < 0.00010) {
			discard;
		}
		float height = sample_height(direction);
		float elevation = is_detail ? detail_elevation : (height * 2.0 - 1.0) * elevation_scale;
		float snow = smoothstep(0.68, 0.85, abs(direction.y) + max(elevation, 0.0) / 6.0);
		vec3 land = mix(vec3(0.12, 0.30, 0.13), vec3(0.36, 0.39, 0.32), smoothstep(1.0, 3.5, elevation));
		land = mix(vec3(0.64, 0.65, 0.42), land, smoothstep(0.0, 0.15, elevation));
		if (has_environment) {
			int biome = int(round(sample_environment(direction).g * 7.0));
			if (biome == 4) { land = vec3(0.33, 0.49, 0.23); }
			if (biome == 5) { land = vec3(0.10, 0.27, 0.12); }
			if (biome == 6) { land = vec3(0.36, 0.39, 0.32); }
			if (biome == 7) { snow = 1.0; }
		}
		ALBEDO = mix(land, vec3(0.88, 0.94, 0.96), snow);
		vec3 slope_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		NORMAL = dot(slope_normal, NORMAL) < 0.0 ? -slope_normal : slope_normal;
		if (water_pass) {
			float level = 0.0;
			if (has_environment) {
				vec2 environment = sample_environment(direction);
				int biome = int(round(environment.g * 7.0));
				if (biome != 0 && biome != 1) { discard; }
				level = (environment.r * 2.0 - 1.0) * elevation_scale;
			}
			if (elevation > level) { discard; }
			ALBEDO = mix(vec3(0.035, 0.25, 0.38), vec3(0.08, 0.43, 0.48), exp(-max(level - elevation, 0.0) * 8.0));
			vec3 wave_point = is_detail ? local_point : direction * planet_radius;
			float waves = sin(dot(wave_point, vec3(1.0, 0.7, 0.3)) * 650.0 + wave_phase.x + TIME * 0.8) * cos(dot(wave_point, vec3(0.2, 0.5, 1.0)) * 700.0 + wave_phase.y + TIME * 0.6);
			ALBEDO *= 1.0 + waves * 0.08;
			ROUGHNESS = 0.28;
		}
	}
}