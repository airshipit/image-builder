package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestJson2Yaml(t *testing.T) {
	tc := []struct {
		in  string
		out string
		err error
	}{
		{
			in: `
{
    "ansible_check_mode": false,
    "ansible_config_file": "/home/ubuntu/.ansible.cfg"
}`,
			out: `ansible_check_mode: false
ansible_config_file: /home/ubuntu/.ansible.cfg
`,
		},
	}

	for _, ti := range tc {
		rOut, rErr := Json2Yaml([]byte(ti.in))

		if ti.err != nil || rErr != nil {
			assert.Equal(t, ti.err, rErr)
		} else {
			assert.Equal(t, ti.out, string(rOut))
		}
	}
}
