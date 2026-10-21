shader_type spatial;
uniform vec4 base_color:source_color=vec4(.5,.35,.2,1);
uniform bool wood=true;
varying vec3 p;
float hash(vec3 v){return fract(sin(dot(v,vec3(12.9898,78.233,39.425)))*43758.5453);}
void vertex(){p=VERTEX;}
void fragment(){
	float grain;
	if(wood){
		grain=sin(p.x*95.0+sin(p.y*1.6+p.z*7.0)*3.0+sin(p.y*8.0)*.3)*.5+.5;
		grain=mix(grain,hash(floor(p*vec3(180,9,130))),.12);
	}else{
		grain=hash(floor(p*72.0))*.20+sin(p.x*7.0+p.z*13.0)*.1+.5;
	}
	ALBEDO=base_color.rgb*(.77+grain*.36);
	ROUGHNESS=.94;
	SPECULAR=.17;
}
