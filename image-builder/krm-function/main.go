/*
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
     https://www.apache.org/licenses/LICENSE-2.0
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
*/

package main

import (
	"encoding/json"
	"fmt"
	"os"

	"sigs.k8s.io/kustomize/kyaml/fn/framework"
	"sigs.k8s.io/kustomize/kyaml/fn/framework/command"
	"sigs.k8s.io/kustomize/kyaml/yaml"
)

const (
	defaultConfigPath = "/profiles/profile_multistrap.json"
)

type Config struct {
	Data struct {
		Header     string `json:"header,omitempty" yaml:"header,omitempty"`
		ConfigPath string `json:"configPath,omitempty" yaml:"configPath,omitempty"`
	} `json:"data,omitempty" yaml:"data,omitempty"`
}

func (c *Config) Process(rl *framework.ResourceList) error {
	if err := framework.LoadFunctionConfig(rl.FunctionConfig, c); err != nil {
		return fmt.Errorf("Can't load config: %v", err)
	}

	j, err := os.ReadFile(c.Data.ConfigPath)
	if err != nil {
		return fmt.Errorf("Can't read file: %v", err)
	}
	y, err := Json2Yaml(j)
	if err != nil {
		return err
	}
	hy := c.Data.Header + string(y)
	r, err := yaml.Parse(hy)
	if err != nil {
		return fmt.Errorf("Can't parse resulting yaml %s: %v", hy, err)
	}
	rl.Items = append(rl.Items, r)
	return nil
}

func Json2Yaml(j []byte) ([]byte, error) {
	var content interface{}

	if err := json.Unmarshal(j, &content); err != nil {
		return nil, fmt.Errorf("Can't unmarshal %s: %v", string(j), err)
	}

	y, err := yaml.Marshal(content)
	if err != nil {
		return nil, fmt.Errorf("Can't marshal %v: %v", content, err)
	}

	return y, nil
}

func main() {
	config := Config{}
	config.Data.ConfigPath = defaultConfigPath

	cmd := command.Build(&config, command.StandaloneDisabled, false)

	if err := cmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
