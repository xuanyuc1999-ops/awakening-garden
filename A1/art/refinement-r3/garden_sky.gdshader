shader_type sky;
uniform float daylight = 1.0;
uniform bool moon_garden = false;
float hash2(vec2 p) {return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise2(vec2 p) {
	vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);
	return mix(mix(hash2(i),hash2(i+vec2(1,0)),f.x),mix(hash2(i+vec2(0,1)),hash2(i+vec2(1,1)),f.x),f.y);
}
void sky() {
	float h = clamp(EYEDIR.y,0.0,1.0);
	vec3 top=mix(vec3(.045,.07,.15),vec3(.23,.48,.68),daylight);
	vec3 horizon=mix(vec3(.18,.23,.34),vec3(.74,.80,.73),daylight);
	if(moon_garden) {
		top=mix(vec3(.035,.045,.12),vec3(.24,.32,.48),daylight);
		horizon=mix(vec3(.22,.26,.40),vec3(.53,.60,.69),daylight);
	}
	vec3 col=mix(horizon,top,pow(h,.55));
	vec2 uv=EYEDIR.xz/max(.12,EYEDIR.y+.18);
	float n=noise2(uv*.6+vec2(TIME*.002,0.0))*.65+noise2(uv*1.4)*.25+noise2(uv*3.0)*.10;
	float clouds=smoothstep(.55,.76,n)*smoothstep(.02,.22,h);
	col=mix(col,mix(vec3(.32,.36,.46),vec3(.94,.91,.80),daylight),clouds*.63);
	float disc=smoothstep(.9990,.9995,dot(EYEDIR,normalize(vec3(-.36,.34,-.86))));
	float halo=pow(max(0.0,dot(EYEDIR,normalize(vec3(-.36,.34,-.86)))),75.0);
	col+=halo*vec3(.15,.18,.27)*(1.0-daylight*.8);
	col=mix(col,vec3(.91,.94,1.0),disc*(1.0-daylight*.75));
	float stars=step(.9975,hash2(floor(SKY_COORDS*vec2(1200,600))))*pow(1.0-daylight,2.0)*smoothstep(.1,.5,h);
	col+=vec3(stars*.6);
	// Distant layered ridgelines sit behind the real, parallax-producing crags.
	float azimuth=atan(EYEDIR.z,EYEDIR.x);
	for(int layer=0;layer<3;layer++){
		float k=float(layer);
		float ridge=.035+.045*noise2(vec2(azimuth*4.0+k*7.0,3.0+k))
			+.035*abs(sin(azimuth*(5.0+k)+k*2.3))-.045*k;
		float mask=1.0-smoothstep(ridge-.002,ridge+.002,EYEDIR.y);
		vec3 mountain=mix(vec3(.13,.20,.18),vec3(.25,.35,.29),daylight)*(1.0-k*.09);
		if(moon_garden){mountain=mix(vec3(.075,.10,.19),vec3(.20,.25,.38),daylight)*(1.0-k*.10);}
		col=mix(col,mountain,mask*.65);
	}
	float depth_mist=smoothstep(0.0,.65,-EYEDIR.y);
	vec3 valley_mist=moon_garden ? vec3(.25,.30,.44) : mix(vec3(.12,.18,.20),vec3(.48,.57,.48),daylight);
	col=mix(col,valley_mist,depth_mist*.84);
	COLOR=col;
}
