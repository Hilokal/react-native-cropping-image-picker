# react-native-cropping-image-picker

iOS/Android image picker with support for camera, video, configurable compression, multiple images and cropping.

⚠️ This library is a comprehensive rework of [`react-native-image-crop-picker`](https://github.com/ivpusic/react-native-image-crop-picker)

Our primary motivation for this overhaul was the inadequate support for the GIF format in the original library. However, it's important to note that `react-native-image-crop-picker` is not abandoned. Therefore, we don't aim to replace it. Instead, we present an alternative. Users should choose the package that best suits their needs.

In our version, we have completely rewritten the library using Swift and Kotlin, ensuring modern standards. We've also removed outdated dependencies and replaced those that are no longer actively maintained. For ease of transition and compatibility, we've retained the exposed functions and types from `react-native-image-crop-picker`.

## Installation

```sh
npm install react-native-cropping-image-picker
```

## Usage (TODO)

```ts
import {
  clean,
  cleanSingle,
  openCamera,
  openCropper,
  openPicker,
  openLimitedAccessConfirmDialog,
  queryAccessStatus,
} from 'react-native-cropping-image-picker';

// ...

await clean();
await cleanSingle();
await openCamera();
await openCropper();
await openPicker();
await openLimitedAccessConfirmDialog();
await queryAccessStatus();
```

- See [`react-native-image-crop-picker`](https://github.com/ivpusic/react-native-image-crop-picker/blob/master/README.md)'s documentation for detailed instructions.
- See the example app for more detailed usage examples.

### ⚠️ iOS Only ⚠️

- `openLimitedAccessConfirmDialog`

  Shows the user a dialog with two options:

1. Add images to the granted access scope

   (Will show the image picker with the already selected images marked)

2. Grant full access

   (Will open the app settings, the user will have to navigate to the image permissions submenu)

- `queryAccessStatus`

  Will return the current access status, possible values are:

  - limited (Limited selection of images selected)
  - denied (no access granted at all)
  - unknown (no access requested yet)
  - forbidden (no permission can requested, example would be "Parenting Mode")
  - full (full access granted)

  See: https://developer.apple.com/documentation/photokit/phauthorizationstatus

## Contributing

See the [contributing guide](CONTRIBUTING.md) to learn how to contribute to the repository and the development workflow.

## License

MIT

---

Made with [create-react-native-library](https://github.com/callstack/react-native-builder-bob)
