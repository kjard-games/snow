#version 330

// Input from vertex shader
in vec3 fragTexCoord;

// Cubemap texture sampler
uniform samplerCube textureCubemap;

// Output fragment color
out vec4 finalColor;

void main()
{
    // Sample the cubemap using the direction vector
    finalColor = texture(textureCubemap, fragTexCoord);
}
