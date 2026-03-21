package release

import (
	"encoding/json"
	"fmt"
)

type ReleaseStep struct {
	Kind        string `json:"kind"`
	Path        string `json:"path,omitempty"`
	Text        string `json:"text,omitempty"`
	Regex       string `json:"regex,omitempty"`
	Replacement string `json:"replacement,omitempty"`
	Key         string `json:"key,omitempty"`
	Value       string `json:"value,omitempty"`
}

func decodeReleaseSteps(raw string) ([]ReleaseStep, error) {
	if raw == "" {
		return nil, nil
	}

	var steps []ReleaseStep
	if err := json.Unmarshal([]byte(raw), &steps); err != nil {
		return nil, fmt.Errorf("decode release steps: %w", err)
	}

	for i, step := range steps {
		if err := validateReleaseStep(step); err != nil {
			return nil, fmt.Errorf("release step %d: %w", i+1, err)
		}
	}
	return steps, nil
}

func validateReleaseStep(step ReleaseStep) error {
	switch step.Kind {
	case "writeFile":
		if step.Path == "" {
			return fmt.Errorf("writeFile.path is required")
		}
		return nil
	case "replace":
		if step.Path == "" {
			return fmt.Errorf("replace.path is required")
		}
		if step.Regex == "" {
			return fmt.Errorf("replace.regex is required")
		}
		return nil
	case "versionMetaSet":
		if step.Key == "" {
			return fmt.Errorf("versionMetaSet.key is required")
		}
		return nil
	case "versionMetaUnset":
		if step.Key == "" {
			return fmt.Errorf("versionMetaUnset.key is required")
		}
		return nil
	default:
		return fmt.Errorf("unsupported release step kind %q", step.Kind)
	}
}
