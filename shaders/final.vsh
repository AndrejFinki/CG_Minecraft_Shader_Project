#version 120

varying vec2 TexCoords;

void
main()
{
    gl_Position = ftransform();
    TexCoords = gl_MultiTexCoord0.st;
}