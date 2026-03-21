package release

import (
	"errors"
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

var versionPattern = regexp.MustCompile(`^([0-9]+)\.([0-9]+)\.([0-9]+)(?:-([A-Za-z]+)\.([0-9]+))?$`)

type Version struct {
	Major      int
	Minor      int
	Patch      int
	Channel    string
	Prerelease int
}

func ParseVersion(raw string) (Version, error) {
	match := versionPattern.FindStringSubmatch(raw)
	if match == nil {
		return Version{}, fmt.Errorf("invalid version %q (expected x.y.z or x.y.z-channel.N)", raw)
	}

	major, _ := strconv.Atoi(match[1])
	minor, _ := strconv.Atoi(match[2])
	patch, _ := strconv.Atoi(match[3])
	v := Version{
		Major:   major,
		Minor:   minor,
		Patch:   patch,
		Channel: "stable",
	}
	if match[4] != "" {
		pre, _ := strconv.Atoi(match[5])
		v.Channel = match[4]
		v.Prerelease = pre
	}
	return v, nil
}

func (v Version) String() string {
	if v.Channel == "" || v.Channel == "stable" {
		return fmt.Sprintf("%d.%d.%d", v.Major, v.Minor, v.Patch)
	}
	return fmt.Sprintf("%d.%d.%d-%s.%d", v.Major, v.Minor, v.Patch, v.Channel, v.Prerelease)
}

func (v Version) BaseString() string {
	return fmt.Sprintf("%d.%d.%d", v.Major, v.Minor, v.Patch)
}

func (v Version) Tag() string {
	return "v" + v.String()
}

func (v Version) cmp(other Version) int {
	if v.Major != other.Major {
		return compareInt(v.Major, other.Major)
	}
	if v.Minor != other.Minor {
		return compareInt(v.Minor, other.Minor)
	}
	if v.Patch != other.Patch {
		return compareInt(v.Patch, other.Patch)
	}
	if v.Channel == "stable" && other.Channel != "stable" {
		return 1
	}
	if v.Channel != "stable" && other.Channel == "stable" {
		return -1
	}
	if v.Channel == "stable" && other.Channel == "stable" {
		return 0
	}
	if v.Channel != other.Channel {
		return comparePrerelease(v.Channel, other.Channel)
	}
	return compareInt(v.Prerelease, other.Prerelease)
}

func ResolveNextVersion(current Version, args []string, allowedChannels []string) (Version, error) {
	currentFull := current.String()
	action := ""
	rest := args
	if len(rest) > 0 {
		action = rest[0]
		rest = rest[1:]
	}

	if action == "set" {
		return resolveSetVersion(current, currentFull, rest, allowedChannels)
	}

	part := ""
	targetChannel := ""
	wasChannelOnly := false

	switch action {
	case "":
		part = "patch"
	case "major", "minor", "patch":
		part = action
		if len(rest) > 0 {
			targetChannel = rest[0]
			rest = rest[1:]
		}
	case "stable", "full":
		if len(rest) > 0 {
			return Version{}, fmt.Errorf("%q takes no second argument", action)
		}
		targetChannel = "stable"
	default:
		if contains(allowedChannels, action) {
			if len(rest) > 0 {
				return Version{}, errors.New("channel-only bump takes no second argument")
			}
			targetChannel = action
			wasChannelOnly = true
		} else {
			return Version{}, fmt.Errorf("unknown argument %q", action)
		}
	}

	if targetChannel == "" {
		targetChannel = current.Channel
	}
	if err := validateChannel(targetChannel, allowedChannels); err != nil {
		return Version{}, err
	}
	if current.Channel != "stable" && targetChannel == "stable" && action != "stable" && action != "full" {
		return Version{}, fmt.Errorf("from prerelease channel %q, promote using 'stable' or 'full' only", current.Channel)
	}
	if part == "" && wasChannelOnly && current.Channel == "stable" && targetChannel != "stable" {
		part = "patch"
	}

	next := current
	oldBase := next.BaseString()
	oldChannel := next.Channel
	oldPre := next.Prerelease
	if part != "" {
		bumpVersion(&next, part)
	}

	if targetChannel == "stable" {
		next.Channel = "stable"
		next.Prerelease = 0
	} else {
		if next.BaseString() == oldBase && targetChannel == oldChannel && oldPre > 0 {
			next.Prerelease = oldPre + 1
		} else {
			next.Prerelease = 1
		}
		next.Channel = targetChannel
	}

	if next.String() == currentFull {
		return Version{}, fmt.Errorf("Version %s is already current; nothing to do.", next.String())
	}

	return next, nil
}

func resolveSetVersion(current Version, currentFull string, args []string, allowedChannels []string) (Version, error) {
	if len(args) == 0 {
		return Version{}, errors.New("'set' requires a version argument")
	}
	next, err := ParseVersion(args[0])
	if err != nil {
		return Version{}, err
	}
	if err := validateChannel(next.Channel, allowedChannels); err != nil {
		return Version{}, err
	}
	if current.Channel != "stable" && next.Channel == "stable" {
		return Version{}, fmt.Errorf("from prerelease channel %q, promote using 'stable' or 'full' only", current.Channel)
	}
	switch next.cmp(current) {
	case 0:
		return Version{}, fmt.Errorf("Version %s is already current; nothing to do.", next.String())
	case -1:
		return Version{}, fmt.Errorf("%s is lower than current %s", next.String(), currentFull)
	}
	return next, nil
}

func validateChannel(channel string, allowedChannels []string) error {
	if channel == "" || channel == "stable" {
		return nil
	}
	if contains(allowedChannels, channel) {
		return nil
	}
	return fmt.Errorf("unknown channel %q", channel)
}

func bumpVersion(v *Version, part string) {
	switch part {
	case "major":
		v.Major++
		v.Minor = 0
		v.Patch = 0
	case "minor":
		v.Minor++
		v.Patch = 0
	case "patch":
		v.Patch++
	default:
		panic("unknown bump part: " + part)
	}
}

func compareInt(left int, right int) int {
	switch {
	case left > right:
		return 1
	case left < right:
		return -1
	default:
		return 0
	}
}

func comparePrerelease(left string, right string) int {
	values := []string{left, right}
	sort.Slice(values, func(i int, j int) bool {
		return semverLikeLess(values[i], values[j])
	})
	switch {
	case left == right:
		return 0
	case values[len(values)-1] == left:
		return 1
	default:
		return -1
	}
}

func semverLikeLess(left string, right string) bool {
	leftParts := strings.FieldsFunc(left, func(r rune) bool { return r == '.' || r == '-' })
	rightParts := strings.FieldsFunc(right, func(r rune) bool { return r == '.' || r == '-' })
	for i := 0; i < len(leftParts) && i < len(rightParts); i++ {
		li, lerr := strconv.Atoi(leftParts[i])
		ri, rerr := strconv.Atoi(rightParts[i])
		switch {
		case lerr == nil && rerr == nil:
			if li != ri {
				return li < ri
			}
		default:
			if leftParts[i] != rightParts[i] {
				return leftParts[i] < rightParts[i]
			}
		}
	}
	return len(leftParts) < len(rightParts)
}
