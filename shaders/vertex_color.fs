#version 330

// Input from vertex shader
in vec4 fragColor;

// Output fragment color
out vec4 finalColor;

void main()
{
    // Output the interpolated vertex color
    finalColor = fragColor;
}