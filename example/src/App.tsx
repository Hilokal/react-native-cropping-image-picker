import * as React from 'react';

import {
  StyleSheet,
  SafeAreaView,
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  Image,
  Alert,
  type ImageSourcePropType,
  Platform,
} from 'react-native';
import Video from 'react-native-video';
import {
  clean,
  cleanSingle,
  openCamera,
  openCropper,
  openPicker,
  openLimitedAccessConfirmDialog,
  queryAccessStatus,
} from 'react-native-cropping-image-picker';

type Asset = {
  uri: string;
  width: number;
  height: number;
  mime?: string;
};

export default function App() {
  const [state, setState] = React.useState<
    | {
        image?: Asset | null;
        images?: Asset[] | null;
      }
    | undefined
  >();

  function pickSingleWithCamera(
    cropping: boolean,
    mediaType: 'photo' | 'video' = 'photo'
  ) {
    openCamera({
      cropping: cropping,
      width: 1024,
      height: 1024,
      includeExif: true,
      mediaType,
    })
      .then((image) => {
        console.log('received image', image);
        setState({
          image: {
            uri: image.path,
            width: image.width,
            height: image.height,
            mime: image.mime,
          },
          images: null,
        });
      })
      .catch((e) => console.error(e));
  }

  function pickSingleBase64(cropit: boolean) {
    openPicker({
      width: 1024,
      height: 1024,
      cropping: cropit,
      includeBase64: true,
      includeExif: true,
    })
      .then((image) => {
        console.log('received base64 image');
        if ('data' in image) {
          setState({
            image: {
              uri: `data:${image.mime};base64,` + image.data,
              width: image.width,
              height: image.height,
            },
            images: null,
          });
        }
      })
      .catch((e) => console.error(e));
  }

  function cleanupImages() {
    clean()
      .then(() => {
        console.log('removed tmp images from tmp directory');
      })
      .catch((e) => {
        console.error(e);
      });
  }

  function cleanupSingleImage() {
    let image =
      state?.image ||
      (state?.images && state.images.length ? state.images[0] : null);
    console.log('will cleanup image', image);

    if (image && image?.uri) {
      cleanSingle(image.uri)
        .then(() => {
          if (state?.image && state?.image?.uri === image?.uri) {
            setState({ image: null });
          }
          if (state?.images) {
            const updatedImages = state.images.filter(
              (img: Asset) => img.uri !== image?.uri
            );
            setState((prevState) => ({ ...prevState, images: updatedImages }));
          }
          console.log(`removed tmp image ${image?.uri} from tmp directory`);
        })
        .catch((e) => {
          console.error(e);
        });
    }
  }

  function cropLast() {
    if (!state?.image) {
      return Alert.alert(
        'No image',
        'Before open cropping only, please select image'
      );
    }

    openCropper({
      path: state?.image.uri,
      width: 512,
      height: 512,
      mediaType: 'photo',
      forceJpg: true,
      cropperChooseColor: '#EE00DD',
    })
      .then((image) => {
        console.log('received cropped image', image);
        setState({
          image: {
            uri: image.path,
            width: image.width,
            height: image.height,
            mime: image.mime,
          },
          images: null,
        });
      })
      .catch((e) => {
        console.log(e);
        Alert.alert(e.message ? e.message : e);
      });
  }

  function pickSingle(cropit: boolean, circular: boolean = false) {
    openPicker({
      width: 1024,
      height: 1024,
      cropping: cropit,
      cropperCircleOverlay: circular,
      sortOrder: 'none',
      compressImageMaxWidth: 2048,
      compressImageMaxHeight: 2048,
      compressImageQuality: 1,
      compressVideoPreset: 'MediumQuality',
      includeExif: true,
      cropperStatusBarColor: 'white',
      cropperToolbarColor: 'white',
      cropperActiveWidgetColor: 'white',
      cropperToolbarWidgetColor: '#3498DB',
      switchDimensionsOnOrientation: true,
    })
      .then((image) => {
        console.log('received image', image);
        if (cropit) {
          openCropper({
            path: image.path,
            width: 512,
            height: 512,
            mediaType: 'photo',
            forceJpg: true,
            cropperCircleOverlay: circular,
          })
            .then((i) => {
              console.log('received cropped image', i);
              setState({
                image: {
                  uri: i.path,
                  width: i.width,
                  height: i.height,
                  mime: i.mime,
                },
                images: null,
              });
            })
            .catch((e) => {
              console.log(e);
              Alert.alert(e.message ? e.message : e);
            });
        } else {
          setState({
            image: {
              uri: image.path,
              width: image.width,
              height: image.height,
              mime: image.mime,
            },
            images: null,
          });
        }
      })
      .catch((e) => {
        console.log(e);
        Alert.alert(e.message ? e.message : e);
      });
  }

  function pickMultiple() {
    try {
      openPicker({
        multiple: true,
        waitAnimationEnd: false,
        sortOrder: 'desc',
        includeExif: true,
        forceJpg: true,
      })
        .then((images) => {
          setState({
            image: null,
            images: images.map((i) => {
              console.log('received image', i);
              return {
                uri: i.path,
                width: i.width,
                height: i.height,
                mime: i.mime,
              };
            }),
          });
        })
        .catch((e) => console.error(e));
    } catch (error) {
      console.error(error);
    }
  }

  function showLimitedAccessConfirmDialog() {
    openLimitedAccessConfirmDialog({ dialogTitle: 'Custom Title!' }).catch(
      (e) => console.error(e)
    );
  }

  function pickSingleWithGifSupport(circular: boolean = false) {
    openPicker({
      cropping: false,
      cropperCircleOverlay: circular,
      sortOrder: 'none',
      includeExif: true,
      cropperStatusBarColor: 'white',
      cropperToolbarColor: 'white',
      cropperActiveWidgetColor: 'white',
      cropperToolbarWidgetColor: '#3498DB',
      mediaType: 'photo',
      switchDimensionsOnOrientation: true,
    })
      .then((image) => {
        console.log('received image', image);
        openCropper({
          path: image.path,
          width: 512,
          height: 512,
          mediaType: 'photo',
          forceJpg: true,
        })
          .then((i) => {
            console.log('received cropped image', i);
            setState({
              image: {
                uri: i.path,
                width: i.width,
                height: i.height,
                mime: i.mime,
              },
              images: null,
            });
          })
          .catch((e) => {
            console.log(e);
            Alert.alert(e.message ? e.message : e);
          });
      })
      .catch((e) => {
        console.log(e);
        Alert.alert(e.message ? e.message : e);
      });
  }

  async function onQueryAccessStatus() {
    const result = await queryAccessStatus();
    Alert.alert('Image Access Level', `${result}`);
  }

  function renderVideo(video: Asset) {
    console.log('rendering video');
    return (
      <View style={styles.videoContainer}>
        <Video
          source={{ uri: video.uri, type: video.mime }}
          style={styles.video}
          rate={1}
          paused={false}
          volume={1}
          muted={false}
          resizeMode={'cover'}
          onError={(e) => console.log(e)}
          onLoad={(load) => console.log(load)}
          repeat={true}
        />
      </View>
    );
  }

  function renderImage(image: ImageSourcePropType) {
    return <Image style={styles.image} source={image} />;
  }

  function renderAsset(image: Asset) {
    if (image.mime && image.mime.toLowerCase().indexOf('video/') !== -1) {
      return renderVideo(image);
    }

    return renderImage(image);
  }

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.assetView}>
        {state?.image ? renderAsset(state?.image) : null}
        {state?.images
          ? state?.images.map((i) => <View key={i.uri}>{renderAsset(i)}</View>)
          : null}
      </ScrollView>

      <ScrollView style={styles.buttonView}>
        <TouchableOpacity
          onPress={() => pickSingleWithCamera(false)}
          style={styles.button}
        >
          <Text style={styles.text}>Select Single Image With Camera</Text>
        </TouchableOpacity>
        <TouchableOpacity
          onPress={() => pickSingleWithCamera(false, 'video')}
          style={styles.button}
        >
          <Text style={styles.text}>Select Single Video With Camera</Text>
        </TouchableOpacity>
        <TouchableOpacity
          onPress={() => pickSingleWithCamera(true)}
          style={styles.button}
        >
          <Text style={styles.text}>
            Select Single With Camera With Cropping
          </Text>
        </TouchableOpacity>
        <TouchableOpacity
          onPress={() => pickSingle(false, false)}
          style={styles.button}
        >
          <Text style={styles.text}>Select Single</Text>
        </TouchableOpacity>
        <TouchableOpacity onPress={() => cropLast()} style={styles.button}>
          <Text style={styles.text}>Crop Last Selected Image</Text>
        </TouchableOpacity>
        <TouchableOpacity
          onPress={() => pickSingleBase64(false)}
          style={styles.button}
        >
          <Text style={styles.text}>Select Single Returning Base64</Text>
        </TouchableOpacity>
        <TouchableOpacity
          onPress={() => pickSingle(true)}
          style={styles.button}
        >
          <Text style={styles.text}>Select Single With Cropping</Text>
        </TouchableOpacity>
        <TouchableOpacity
          onPress={() => pickSingle(true, true)}
          style={styles.button}
        >
          <Text style={styles.text}>Select Single With Circular Cropping</Text>
        </TouchableOpacity>
        <TouchableOpacity
          onPress={() => pickSingleWithGifSupport()}
          style={styles.button}
        >
          <Text style={styles.text}>
            Select Single with Gif-Support and Cropping
          </Text>
        </TouchableOpacity>
        <TouchableOpacity onPress={pickMultiple} style={styles.button}>
          <Text style={styles.text}>Select Multiple</Text>
        </TouchableOpacity>
        {Platform.OS === 'ios' && (
          <TouchableOpacity
            onPress={showLimitedAccessConfirmDialog}
            style={styles.button}
          >
            <Text style={styles.text}>
              Show Limited Access Confirmation Dialog
            </Text>
          </TouchableOpacity>
        )}
        {Platform.OS === 'ios' && (
          <TouchableOpacity onPress={onQueryAccessStatus} style={styles.button}>
            <Text style={styles.text}>Query Access Status</Text>
          </TouchableOpacity>
        )}
        <TouchableOpacity onPress={cleanupImages} style={styles.button}>
          <Text style={styles.text}>Cleanup All Images</Text>
        </TouchableOpacity>
        <TouchableOpacity onPress={cleanupSingleImage} style={styles.button}>
          <Text style={styles.text}>Cleanup Single Image</Text>
        </TouchableOpacity>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    width: '100%',
    justifyContent: 'center',
    alignItems: 'center',
  },
  assetView: {
    flex: 1,
    marginBottom: 10,
  },
  buttonView: {
    flex: 1,
    width: '100%',
    borderTopWidth: 2,
    borderTopColor: 'white',
    paddingTop: 10,
    marginBottom: 10,
  },
  button: {
    backgroundColor: 'blue',
    width: '90%',
    marginStart: 'auto',
    marginEnd: 'auto',
    marginBottom: 10,
    borderRadius: 20,
  },
  text: {
    color: 'white',
    fontSize: 20,
    textAlign: 'center',
    padding: 10,
  },
  image: {
    width: 300,
    height: 300,
    resizeMode: 'contain',
  },
  videoContainer: {
    height: 300,
    width: 300,
    marginVertical: 5,
    marginStart: 'auto',
    marginEnd: 'auto',
  },
  video: {
    position: 'absolute',
    top: 0,
    left: 0,
    bottom: 0,
    right: 0,
  },
});
