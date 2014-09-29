//
//  WorldCreatorViewController.m
//  Galileo's Sandbox
//
//  Created by Conner Douglass on 6/4/14.
//  Copyright (c) 2014 Conner Douglass. All rights reserved.
//

#import "WorldCreatorViewController.h"

#define RINGS_INNER_COLOR_MULTIPLIER 0.6f

#define MAX_DISTANCE_MOON 50.0f
#define MIN_DISTANCE_MOON 5.0f
#define MIN_RADIUS 0.01f
#define MAX_RADIUS 1.0f

#define TWEEN(min,max,p) (min+(max-min)*p)
#define BETWEEN(val,min,max) ((val-min)/(max-min))

@interface WorldCreatorViewController () <UIAlertViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITextFieldDelegate>

@property UIAlertView *cancelAlertView;
@property NSInteger currentPhase;
@property NSMutableDictionary *textureButtonTextures, *ringButtonTextures, *orbitingParents;
@property OpenGLView *previewView;
@property WorldPreviewScene *previewScene;
@property UIPopoverController *popover;
@property UIImage *worldTextureImage;
@property NSString *worldTextureName;
@property NSString *ringsTextureName;

@end

@implementation WorldCreatorViewController

+ (NSMutableArray *)userWorldJSONData
{
    NSData *data = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:USERWORLDS_JSON ofType:@""]];
    
    if(!data) {
        return [NSMutableArray array];
    }
    
    NSError *error;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
    if(error) {
        NSLog(@"%@", error);
    }
    
    NSMutableArray *bodies = [NSMutableArray arrayWithArray:[json objectForKey:@"bodies"]];
    return bodies;
}

+ (BOOL)worldExistsWithKey:(NSString *)key value:(NSString *)value
{
    NSMutableArray *bodies = [WorldCreatorViewController userWorldJSONData];
    for(NSDictionary *body in bodies) {
        NSString *worldValue = [body valueForKey:key];
        if([worldValue isEqualToString:value]) {
            return YES;
        }
    }
    return NO;
}

+ (void)saveUserWorldWithDictionary:(NSDictionary *)worldDictionary
{
    NSString *newWorldId = [worldDictionary valueForKey:@"id"];
    
    NSMutableArray *bodies = [WorldCreatorViewController userWorldJSONData];
    NSDictionary *bodyToOverride = nil;
    for(NSDictionary *body in bodies) {
        NSString *bodyId = [body valueForKey:@"id"];
        if([bodyId isEqualToString:newWorldId]) {
            bodyToOverride = body;
        }
    }
    if(bodyToOverride) {
        [bodies removeObject:bodyToOverride];
    }
    [bodies addObject:worldDictionary];
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:worldDictionary options:kNilOptions error:&error];
    if (!jsonData) {
        NSLog(@"Error saving user world: %@", error);
        return;
    }
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,  NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *appFile = [documentsDirectory stringByAppendingPathComponent:USERWORLDS_JSON];
    [jsonString writeToFile:appFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (void)loadDataForIdentifier:(NSString *)identifier
{
    self.existingWorldIdentifier = identifier;
}

- (void)loadData
{
    [WorldDataManager fetchJsonForBodyWithIdentifier:self.existingWorldIdentifier completion:^(NSDictionary *json) {
        
        GSWorldData *data = [[GSWorldData alloc] initWithJson:json];
        
        BOOL isMoon = [data.type isEqualToString:@"moon"];
        BOOL isPlanet = !isMoon;
        
        self.worldTextureName = data.texture0;
        [self.previewScene setPlanetTexture:[[Texture alloc] initWithImageNamed:self.worldTextureName inView:self.previewView]];
        
        self.planetOrMoonControl.selectedSegmentIndex = isPlanet ? 0 : 1;
        [self didSelectMoonOrPlanet:self.planetOrMoonControl];
        
        self.planetNameField.text = data.name;
        [self didChangeNameOfWorld:self.planetNameField];
        
        [PlanetButton fetchTextureImageWithIdentifier:self.existingWorldIdentifier completion:^(UIImage *textureImage) {
            
            [self.previewScene setPlanetTexture:[[Texture alloc] initWithImage:textureImage inView:self.previewView]];
            
        }];
        
        if(data.rings.enabled) {
            
            [self.previewScene setRingColor:CC3Vector4Make(data.rings.color.x,
                                                           data.rings.color.y,
                                                           data.rings.color.z, 1.0f)];
            [self.previewScene setRingsEnabled:data.rings.enabled];
            self.ringsTextureName = data.rings.texture;
            [self.previewScene setRingTexture:[[Texture alloc] initWithImageNamed:self.ringsTextureName inView:self.previewView]];
        }
        
        if(data.glow.enabled) {
            
            self.previewScene.planet.atmosphereGlowEnabled = YES;
            self.previewScene.planet.atmosphereGlowInnerColor = data.glow.innerColor;
            self.previewScene.planet.atmosphereGlowOuterColor = data.glow.outerColor;
            self.glowEnabled.on = YES;
            
        }
        
        self.axialTiltSlider.value = data.tilt;
        [self didSlideAxialTiltSlider:self.axialTiltSlider];
        
        if(isMoon) {
            self.orbitDistance.value = BETWEEN(data.distance, MIN_DISTANCE_MOON, MIN_DISTANCE_MOON);
        }
        
        self.radiusSlider.value = BETWEEN(data.radius, MIN_RADIUS, MAX_RADIUS);
        
    }];
}

- (id)init
{
    if(self = [super init]) {
        
        self.existingWorldIdentifier = nil;
        
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [UIApplication sharedApplication].statusBarHidden = YES;
    
    [self.planetNameField addTarget:self action:@selector(didChangeNameOfWorld:) forControlEvents:UIControlEventEditingChanged];
    
    NSInteger previewWidth = 260;
    NSInteger previewHeight = 260;
    
    self.previewView = [[OpenGLView alloc] initWithFrame:CGRectMake(20,  CGRectGetMinY(self.parentPhaseContainer.frame) + CGRectGetHeight(self.parentPhaseContainer.bounds) - 20 - previewHeight, previewWidth, previewHeight)];
    
    self.previewScene = [[WorldPreviewScene alloc] init];
    if(self.existingWorldIdentifier) {
        [self loadData];
    }else{
        self.worldTextureName = @"mercury.jpg";
        [self.previewScene setPlanetTexture:[[Texture alloc] initWithImageNamed:self.worldTextureName inView:self.previewView]];
    }
    [self.previewView presentScene:self.previewScene];
    
    [self didSlideGlowColorSlider];
    
    [self setupTexturePhase];
    [self setupRingPhase];
    [self setupOrbitingParentPhase];
    
    [self goToPhase:0];
}

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    [self.view bringSubviewToFront:self.toolbarBackgroundView];
    
    CGRect frame = self.toolbarBackgroundView.frame;
    frame.origin.y = 768 - KEYBOARD_HEIGHT_LANDSCAPE - CGRectGetHeight(frame);
    
    self.toolbarBackgroundView.frame = frame;
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    CGRect frame = self.toolbarBackgroundView.frame;
    
    CGFloat frameHeight = CGRectGetHeight(self.view.frame);
    CGFloat toolbarHeight = CGRectGetHeight(self.toolbarBackgroundView.frame);
    
    frame.origin.y = frameHeight - toolbarHeight;
    
    self.toolbarBackgroundView.frame = frame;
}

- (void)setupTexturePhase
{
    [WorldDataManager fetchAvailableBodyJson:^(NSArray *json) {
        
        // Define some standard values
        NSInteger numberOfButtonsTextures = 0;
        NSInteger texButtonHeight = 72;
        
        CGSize buttonSize = CGSizeMake(CGRectGetWidth(self.textureTemplateSelectionScrollView.bounds), texButtonHeight);
        CGSize buttonSizeScaled = CGSizeMake(buttonSize.width * [UIScreen mainScreen].scale, buttonSize.height * [UIScreen mainScreen].scale);
        
        // Create a dictionary for the texture ids that correspond to the textures
        self.textureButtonTextures = [NSMutableDictionary dictionary];
        
        NSMutableArray *arrayOfWorlds = [NSMutableArray arrayWithArray:json];
        [arrayOfWorlds addObject:@{
                                   @"name": @"Grumpy Cat",
                                   @"texture": @"grumpy-cat.jpg"
                                   }];
        [arrayOfWorlds addObject:@{
                                   @"name": @"Baseball",
                                   @"texture": @"baseball.jpg"
                                   }];
        [arrayOfWorlds addObject:@{
                                   @"name": @"Basketball",
                                   @"texture": @"basketball.jpg"
                                   }];
        [arrayOfWorlds addObject:@{
                                   @"name": @"Tennis Ball",
                                   @"texture": @"tennisball.jpg"
                                   }];
        
        // Loop through each available body
        for(NSDictionary *worldDictionary in arrayOfWorlds) {
            
            if([worldDictionary[@"package"] isEqualToString:PACKAGE_USERWORLDS]) {
                continue;
            }
            
            GSWorldData *data = [[GSWorldData alloc] initWithJson:worldDictionary];
            
            NSString *name = data.name;
            NSString *name2 = [name stringByAppendingString:@" (Night)"];
            NSString *texture1 = data.texture0;
            NSString *texture2 = data.texture1;
            
            if(texture2) {
                name = [name stringByAppendingString:@" (Day)"];
            }
            
            // There will always be a first button
            UIButton *button1 = [UIButton buttonWithType:UIButtonTypeCustom];
            button1.frame = CGRectMake(0, texButtonHeight * numberOfButtonsTextures, CGRectGetWidth(self.textureTemplateSelectionScrollView.bounds), texButtonHeight);
            [button1 setTitle:name forState:UIControlStateNormal];
            [button1 setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [button1 setTitleShadowColor:[UIColor blackColor] forState:UIControlStateNormal];
            [button1 addTarget:self action:@selector(didSelectTextureButton:) forControlEvents:UIControlEventTouchUpInside];
            
            NSString *path1 = [[NSBundle mainBundle] pathForResource:texture1 ofType:@""];
            UIImage *image1 = [[UIImage alloc] initWithContentsOfFile:path1];
            
            [button1 setBackgroundImage:[image1 fitToSize:buttonSizeScaled] forState:UIControlStateNormal];
            [self.textureTemplateSelectionScrollView addSubview:button1];
            [self.textureButtonTextures setValue:button1 forKey:texture1];
            numberOfButtonsTextures++;
            
            // Do the same for the second button
            if(texture2) {
                UIButton *button2 = [UIButton buttonWithType:UIButtonTypeCustom];
                button2.frame = CGRectMake(0, texButtonHeight * numberOfButtonsTextures, CGRectGetWidth(self.textureTemplateSelectionScrollView.bounds), texButtonHeight);
                [button2 setTitle:name2 forState:UIControlStateNormal];
                [button2 setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                [button2 setTitleShadowColor:[UIColor blackColor] forState:UIControlStateNormal];
                [button2 addTarget:self action:@selector(didSelectTextureButton:) forControlEvents:UIControlEventTouchUpInside];
                
                NSString *path2 = [[NSBundle mainBundle] pathForResource:texture2 ofType:@""];
                UIImage *image2 = [[UIImage alloc] initWithContentsOfFile:path2];
                // [button2 setBackgroundImage:[image2 fitToSize:buttonSizeScaled] forState:UIControlStateNormal];
                
                [button2 setBackgroundImage:image2 forState:UIControlStateNormal];
                [self.textureTemplateSelectionScrollView addSubview:button2];
                [self.textureButtonTextures setValue:button2 forKey:texture2];
                numberOfButtonsTextures++;
            }
            
        }
        self.textureTemplateSelectionScrollView.contentSize = CGSizeMake(CGRectGetWidth(self.textureTemplateSelectionScrollView.bounds), numberOfButtonsTextures * texButtonHeight);
        
    }];
}

- (void)setupOrbitingParentPhase
{
    [WorldDataManager fetchAvailableBodyJson:^(NSArray *arrayOfWorlds) {
        
        // Define some standard values
        NSInteger numberOfButtonsTextures = 0;
        NSInteger texButtonHeight = 72;
        
        CGSize buttonSize = CGSizeMake(CGRectGetWidth(self.orbitingParentOptionsScrollView.bounds), texButtonHeight);
        CGSize buttonSizeScaled = CGSizeMake(buttonSize.width * [UIScreen mainScreen].scale, buttonSize.height * [UIScreen mainScreen].scale);
        
        // Create a dictionary for the texture ids that correspond to the textures
        self.orbitingParents = [NSMutableDictionary dictionary];
        
        // Loop through each available body
        for(NSDictionary *worldDictionary in arrayOfWorlds) {
            
            GSWorldData *data = [[GSWorldData alloc] initWithJson:worldDictionary];
            
            NSString *name = data.name;
            NSString *type = data.type;
            NSString *identifier = data.identifier;
            
            if(![type isEqualToString:@"planet"]) {
                continue;
            }
            
            // There will always be a first button
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            button.frame = CGRectMake(0, texButtonHeight * numberOfButtonsTextures, CGRectGetWidth(self.orbitingParentOptionsScrollView.bounds), texButtonHeight);
            [button setTitle:name forState:UIControlStateNormal];
            [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [button setTitleShadowColor:[UIColor blackColor] forState:UIControlStateNormal];
            [button addTarget:self action:@selector(didSelectOrbitingParent:) forControlEvents:UIControlEventTouchUpInside];
            
            [PlanetButton fetchTextureImageWithIdentifier:identifier completion:^(UIImage *image) {
                [button setBackgroundImage:[image fitToSize:buttonSizeScaled] forState:UIControlStateNormal];
            }];
            
            [self.orbitingParentOptionsScrollView addSubview:button];
            [self.orbitingParents setValue:button forKey:identifier];
            numberOfButtonsTextures++;
            
        }
        self.orbitingParentOptionsScrollView.contentSize = CGSizeMake(CGRectGetWidth(self.orbitingParentOptionsScrollView.bounds), numberOfButtonsTextures * texButtonHeight);
        
    }];
}

- (IBAction)didChangeGlowEnabled
{
    self.previewScene.planet.atmosphereGlowEnabled = self.glowEnabled.on;
}

- (IBAction)didSlideGlowColorSlider
{
    CC3Vector color = CC3VectorMake(self.glowSliderRed.value, self.glowSliderGreen.value, self.glowSliderBlue.value);
    self.previewScene.planet.atmosphereGlowOuterColor = color;
    self.previewScene.planet.atmosphereGlowInnerColor = CC3VectorScaleUniform(color, RINGS_INNER_COLOR_MULTIPLIER);
}

- (void)didSelectOrbitingParent:(UIButton *)button
{
    self.parentIdentifier = nil;
    for(NSString *key in self.orbitingParents.allKeys) {
        if([self.orbitingParents objectForKey:key] == button) {
            self.parentIdentifier = key;
        }
    }
    /*
    if(!self.parentIdentifier) {
        self.parentIdentifier = @"sun";Hehe
    }
     */
    
    if(!self.parentIdentifier) {
        self.orbitingParentNameLabel.text = @"Sun";
    }else{
        [WorldDataManager fetchJsonForBodyWithIdentifier:self.parentIdentifier completion:^(NSDictionary *json) {
            
            if(!json) {
                self.orbitingParentNameLabel.text = @"Sun";
            }else{
                self.orbitingParentNameLabel.text = [json valueForKey:@"name"];
            }
            
        }];
    }
    
}

- (void)setupRingPhase
{
    CC3Vector4 color = CC3Vector4Make(0.5f, 0.75f, 1.0f, 1.0f);
    self.ringsColorSliderRed.value = color.x;
    self.ringsColorSliderGreen.value = color.y;
    self.ringsColorSliderBlue.value = color.z;
    [self.previewScene setRingColor:color];
    
    // Define some standard values
    NSInteger numberOfButtonsRings = 0;
    NSInteger ringButtonHeight = 72;
    
    CGSize buttonSize = CGSizeMake(CGRectGetWidth(self.ringsStylesSelectionScrollView.bounds), ringButtonHeight);
    CGSize buttonSizeScaled = CGSizeMake(buttonSize.width * [UIScreen mainScreen].scale, buttonSize.height * [UIScreen mainScreen].scale);
    
    // Create a dictionary for the texture ids that correspond to the textures
    self.ringButtonTextures = [NSMutableDictionary dictionary];
    
    NSMutableArray *ringStylesArray = [NSMutableArray array];
    [ringStylesArray addObject:@{@"name": @"No Rings", @"texture": @""}];
    [ringStylesArray addObject:@{@"name": @"Saturn", @"texture": @"rings1.png"}];
    [ringStylesArray addObject:@{@"name": @"Uranus", @"texture": @"rings2.png"}];
    
    // Loop through each available body
    for(NSDictionary *ringDictionary in ringStylesArray) {
        
        NSString *name = [ringDictionary valueForKey:@"name"];
        NSString *texture = [ringDictionary valueForKey:@"texture"];
        
        // There will always be a first button
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(0, ringButtonHeight * numberOfButtonsRings, CGRectGetWidth(self.ringsStylesSelectionScrollView.bounds), ringButtonHeight);
        [button setTitle:name forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [button setTitleShadowColor:[UIColor blackColor] forState:UIControlStateNormal];
        [button addTarget:self action:@selector(didSelectRingStyleButton:) forControlEvents:UIControlEventTouchUpInside];
        
        if(texture.length > 0) {
            NSString *path = [[NSBundle mainBundle] pathForResource:texture ofType:@""];
            UIImage *image = [[UIImage alloc] initWithContentsOfFile:path];
            image = [image fitToSize:buttonSizeScaled];
            
            [button setBackgroundImage:image forState:UIControlStateNormal];
        }
        [self.ringsStylesSelectionScrollView addSubview:button];
        [self.ringButtonTextures setValue:button forKey:texture];
        numberOfButtonsRings++;
        
    }
    self.ringsStylesSelectionScrollView.contentSize = CGSizeMake(CGRectGetWidth(self.ringsStylesSelectionScrollView.bounds), numberOfButtonsRings * ringButtonHeight);
}

- (void)didSelectTextureButton:(UIButton *)button
{
    NSString *textureId = nil;
    for(NSString *key in self.textureButtonTextures.allKeys) {
        if([self.textureButtonTextures objectForKey:key] == button) {
            textureId = key;
        }
    }
    if(!textureId) {
        return;
    }
    self.worldTextureName = textureId;
    self.worldTextureImage = nil;
    Texture *texture = [[Texture alloc] initWithImageNamed:textureId inView:self.previewView];
    [self.previewScene setPlanetTexture:texture];
}

- (void)didSelectRingStyleButton:(UIButton *)button
{
    NSString *textureId = nil;
    for(NSString *key in self.ringButtonTextures.allKeys) {
        if([self.ringButtonTextures objectForKey:key] == button) {
            textureId = key;
        }
    }
    if(!textureId) {
        return;
    }
    if(textureId.length > 0) {
        Texture *texture = [[Texture alloc] initWithImageNamed:textureId inView:self.previewView];
        [self.previewScene setRingsEnabled:YES];
        [self.previewScene setRingTexture:texture];
        self.ringsTextureName = textureId;
    }else{
        [self.previewScene setRingsEnabled:NO];
        self.ringsTextureName = nil;
    }
}

- (IBAction)didSlideAxialTiltSlider:(UISlider *)slider
{
    CGFloat labelCenterX = ((slider.value - slider.minimumValue) / (slider.maximumValue - slider.minimumValue)) * CGRectGetWidth(slider.frame) + CGRectGetMinX(slider.frame);
    self.axialTiltValueLabel.text = [NSString stringWithFormat:@"%i°", (NSInteger)slider.value];
    [self.axialTiltValueLabel sizeToFit];
    self.axialTiltValueLabel.center = CGPointMake(labelCenterX, self.axialTiltValueLabel.center.y);
    [self.previewScene setAxisTilt:slider.value];
}

- (void)didChangeNameOfWorld:(UITextField *)field
{
    if(self.planetNameField.text.length == 0) {
        self.nextStepButton.alpha = 0.0f;
    }else{
        self.nextStepButton.alpha = 1.0f;
    }
}

- (void)assertMessage:(NSString *)message title:(NSString *)title
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:message delegate:self cancelButtonTitle:@"Okay" otherButtonTitles:nil];
    [alert show];
}

- (IBAction)didTapNextStepButton:(UIButton *)sender
{
    if(self.currentPhase == 0) {
        [self.planetNameField resignFirstResponder];
    }
    
    // the part after the "||" allows us to skip moon-only stuff
    if(self.currentPhase == 6 || (self.currentPhase >= 4 && self.planetOrMoonControl.selectedSegmentIndex == 0)) { // Final step index
        
        [self saveFinal];
        
    }else{
        
        [self goToPhase:self.currentPhase + 1];
    }
}

- (void)saveFinal
{
    BOOL isPlanet = self.planetOrMoonControl.selectedSegmentIndex == 0;
    
    GSWorldData *data = [[GSWorldData alloc] init];
    
    // Save the name
    data.name = self.planetNameField.text;
    
    // Assign an identifier
    if(self.existingWorldIdentifier) {
        data.identifier = self.existingWorldIdentifier;
    }else{
        data.identifier = [NSString stringWithFormat:@"userworld-%i", (NSInteger)floorf(CACurrentMediaTime() * 1000)];
    }
    
    // Package, type, and parent
    data.package = PACKAGE_USERWORLDS;
    data.type = isPlanet ? @"planet" : @"moon";
    data.parentIdentifier = (!isPlanet) ? self.parentIdentifier : nil;
    
    // Distances
    if(!isPlanet) {
        data.distance = TWEEN(MIN_DISTANCE_MOON, MAX_DISTANCE_MOON, self.orbitDistance.value);
        data.orbitPeriod = TWEEN(50000, 100000, self.orbitDistance.value);
        data.radius = TWEEN(MIN_RADIUS, MAX_RADIUS, self.radiusSlider.value);
    }else{
        data.radius = 1.0f;
        data.distance = 0.0f;
        data.orbitPeriod = 0.0f;
    }
    
    // Textures
    // If there is a texture name already used (preset images)
    if(self.worldTextureName) {
        
        // Just use that one because it'll be on the device already
        data.texture0 = self.worldTextureName;
        
    // If there was a chosen image
    }else if(self.worldTextureImage) {
        
        // Create the image file name
        NSString *filenameShort = [data.identifier stringByAppendingString:@"-worldtexture.png"];
        
        // Get the image data
        NSData *imgData = UIImagePNGRepresentation([self.worldTextureImage fixOrientation]);
        
        // Write out the data to the file
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *filename = [docs stringByAppendingPathComponent:filenameShort];
        [imgData writeToFile:filename atomically:YES];
        
        // Use the document file reference
        data.texture0 = [NSString stringWithFormat:@"docs:%@", filenameShort];
    
    }
    
    // Spin and tilt
    data.spin = 0.005f;
    data.tilt = self.axialTiltSlider.value;
    
    // If there are rings
    if(self.ringsTextureName) {
        
        data.rings.enabled = YES;
        data.rings.texture = self.ringsTextureName;
        data.rings.innerRadius = 1.2f;// * data.radius;
        data.rings.outerRadius = 2.4f;// * data.radius;
        data.rings.color = CC3VectorMake(self.ringsColorSliderRed.value,
                                         self.ringsColorSliderGreen.value,
                                         self.ringsColorSliderBlue.value);
        
    }
    
    // No clouds
    
    // If there is glow
    if(self.glowEnabled.on) {
        
        data.glow.enabled = YES;
        data.glow.innerColor = CC3VectorMake(self.glowSliderRed.value * RINGS_INNER_COLOR_MULTIPLIER,
                                             self.glowSliderGreen.value * RINGS_INNER_COLOR_MULTIPLIER,
                                             self.glowSliderBlue.value * RINGS_INNER_COLOR_MULTIPLIER);
        data.glow.outerColor = CC3VectorMake(self.glowSliderRed.value,
                                             self.glowSliderGreen.value,
                                             self.glowSliderBlue.value);
        
    }
    
    // Write everything to the file and dismiss this view controller.
    [WorldDataManager fetchJsonForBodiesInPackage:PACKAGE_USERWORLDS completion:^(NSArray *json) {
        
        NSMutableArray *fileJSON = [NSMutableArray arrayWithArray:json];
        NSMutableArray *toRemove = [NSMutableArray array];
        for(NSDictionary *body in fileJSON) {
            if([[body valueForKey:@"id"] isEqualToString:data.identifier]) {
                [toRemove addObject:body];
            }
        }
        [fileJSON removeObjectsInArray:toRemove];
        
        // Add the new json
        [fileJSON addObject:data.jsonValue];
        
        // Write it to file!
        NSError *error;
        NSData *fileData = [NSJSONSerialization dataWithJSONObject:fileJSON options:kNilOptions error:&error];
        if(error) {
            NSLog(@"%@", error);
        }else{
            NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            NSString *userWorldsPath = [docs stringByAppendingPathComponent:USERWORLDS_JSON];
            [fileData writeToFile:userWorldsPath atomically:YES];
        }
        
        [self.presentingViewController dismissViewControllerAnimated:YES completion:^{
            [GSWorld clearCacheForWorldWithIdentifier:data.identifier];
            [[MainViewController sharedInstance] reloadAvailableWorlds];
        }];
        
    }];
}

/*
- (void)saveFinal2
{
    BOOL isPlanet = self.planetOrMoonControl.selectedSegmentIndex == 0;
    BOOL isMoon = !isPlanet;
    
    NSString *worldName = self.planetNameField.text;
    NSString *worldIdentifier = self.existingWorldIdentifier;
    if(!self.existingWorldIdentifier) {
        worldIdentifier = [NSString stringWithFormat:@"userworld-%i", (NSInteger)floorf(CACurrentMediaTime() * 1000)];
    }
    NSString *worldPackage = @"user";
    NSString *worldType = isPlanet ? @"planet" : @"moon";
    NSString *worldOrbitingParent = isMoon ? self.parentIdentifier : @"sun";
    
    CGFloat minDistance = MIN_DISTANCE_PLANET;
    CGFloat maxDistance = MAX_DISTANCE_PLANET;
    if(isMoon) {
        minDistance = MIN_DISTANCE_MOON;
        maxDistance = MAX_DISTANCE_MOON;
    }
    CGFloat worldDistanceFromParent = self.orbitDistance.value * (maxDistance - minDistance) + minDistance;
    
    CGFloat minRadius = MIN_RADIUS;
    CGFloat maxRadius = MAX_RADIUS;
    CGFloat worldRadius = self.radiusSlider.value * (maxRadius - minRadius) + minRadius;
    
    NSString *worldTextureIdentifier = @"";
    if(self.worldTextureName) {
        worldTextureIdentifier = self.worldTextureName;
    }else if(self.worldTextureImage){
        NSString *filenameShort = [worldIdentifier stringByAppendingString:@"-worldtexture.png"];
        NSData *imgData = UIImagePNGRepresentation([self.worldTextureImage fixOrientation]);
        
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *filename = [docs stringByAppendingPathComponent:filenameShort];
        
        [imgData writeToFile:filename atomically:YES];
        
        worldTextureIdentifier = [NSString stringWithFormat:@"docs:%@", filenameShort];
    }
    
    CC3Vector worldAngVel = CC3VectorMake(0.0f, 0.005f, 0.0f);
    CGFloat worldAxialTilt = self.axialTiltSlider.value;
    
    NSMutableDictionary *world = [NSMutableDictionary dictionary];
    [world setValue:worldName forKey:@"name"];
    [world setValue:worldIdentifier forKey:@"id"];
    [world setValue:worldPackage forKey:@"package"];
    [world setValue:worldType forKey:@"type"];
    [world setObject:@YES forKey:@"enabled"];
    [world setValue:worldOrbitingParent forKey:@"orbiting-parent"];
    [world setValue:worldTextureIdentifier forKey:@"texture"];
    
    NSMutableDictionary *worldProperties = [NSMutableDictionary dictionary];
    [worldProperties setObject:@[@(0.0f), @(0.0f)] forKey:@"mass"];
    [worldProperties setObject:@[@(worldRadius), @(0.0f)] forKey:@"radius"];
    [worldProperties setObject:@[@(0.0f), @(0.0f)] forKey:@"orbiting-velocity"];
    [worldProperties setObject:@{
                                 @"x": @[@(worldAngVel.x), @(0.0f)],
                                 @"y": @[@(worldAngVel.y), @(0.0f)],
                                 @"z": @[@(worldAngVel.z), @(0.0f)]
                                 } forKey:@"angular-velocity"];
    [worldProperties setObject:@[@(worldDistanceFromParent), @(0.0f)] forKey:@"distance-from-parent"];
    [worldProperties setObject:@[@(worldAxialTilt), @(0.0f)] forKey:@"axial-tilt"];
    [world setObject:worldProperties forKey:@"properties"];
    
    NSMutableDictionary *worldRings = [NSMutableDictionary dictionary];
    [worldRings setObject:@(self.ringsTextureName != nil) forKey:@"enabled"];
    [worldRings setObject:@[@(1.2f * worldRadius), @(0.0f)] forKey:@"inner-radius"];
    [worldRings setObject:@[@(2.4f * worldRadius), @(0.0f)] forKey:@"outer-radius"];
    [worldRings setObject:@[@(self.ringsColorSliderRed.value),
                            @(self.ringsColorSliderGreen.value),
                            @(self.ringsColorSliderBlue.value)] forKeyedSubscript:@"color"];
    [worldRings setValue:(self.ringsTextureName ? self.ringsTextureName : @"") forKey:@"texture"];
    [world setObject:worldRings forKey:@"rings"];
    
    NSMutableDictionary *worldClouds = [NSMutableDictionary dictionary];
    [worldClouds setObject:@NO forKey:@"enabled"];
    [worldClouds setObject:@{
                             @"x": @[@(0.0f), @(0.0f)],
                             @"y": @[@(0.0f), @(0.0f)],
                             @"z": @[@(0.0f), @(0.0f)]} forKey:@"angular-velocity"];
    [worldClouds setValue:@"" forKey:@"texture"];
    [world setObject:worldClouds forKey:@"clouds"];
    
    NSMutableDictionary *worldGlow = [NSMutableDictionary dictionary];
    [worldGlow setObject:@(self.glowEnabled.on) forKey:@"enabled"];
    [worldGlow setObject:@[
                           @(self.glowSliderRed.value),
                           @(self.glowSliderGreen.value),
                           @(self.glowSliderBlue.value)] forKey:@"outer"];
    [worldGlow setObject:@[
                           @(self.glowSliderRed.value * RINGS_INNER_COLOR_MULTIPLIER),
                           @(self.glowSliderGreen.value * RINGS_INNER_COLOR_MULTIPLIER),
                           @(self.glowSliderBlue.value * RINGS_INNER_COLOR_MULTIPLIER)] forKey:@"inner"];
    [world setObject:worldGlow forKey:@"glow"];
    
    // Now, "world" is done and needs to be added to the file
    
    [WorldDataManager fetchJsonForBodiesInPackage:PACKAGE_USERWORLDS completion:^(NSArray *json) {
        
        NSMutableArray *fileJSON = [NSMutableArray arrayWithArray:json];
        NSMutableArray *toRemove = [NSMutableArray array];
        for(NSDictionary *body in fileJSON) {
            if([[body valueForKey:@"id"] isEqualToString:worldIdentifier]) {
                [toRemove addObject:body];
            }
        }
        [fileJSON removeObjectsInArray:toRemove];
        
        // Add the new json
        [fileJSON addObject:world];
        
        // Write it to file!
        NSError *error;
        NSData *data = [NSJSONSerialization dataWithJSONObject:fileJSON options:kNilOptions error:&error];
        if(error) {
            NSLog(@"%@", error);
        }else{
            NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            NSString *userWorldsPath = [docs stringByAppendingPathComponent:USERWORLDS_JSON];
            [data writeToFile:userWorldsPath atomically:YES];
        }
        
        [self.presentingViewController dismissViewControllerAnimated:YES completion:^{
            // SOMETHING TO UPDATE CACHE ABOUT THIS IDENTIFIER
            [[MainViewController sharedInstance] reloadAvailableWorlds];
        }];
        
    }];
}
*/

- (IBAction)didTapPreviousStepButton:(UIButton *)sender
{
    [self goToPhase:self.currentPhase - 1];
}

- (void)goToPhase:(NSInteger)phase
{
    [self.view endEditing:YES];
    self.currentPhase = phase;
    // NSArray *phases = @[self.phase_NameAndType, self.phase_PositionAndSize, self.phase_Rings, self.phase_TextureTemplateAndColor];
    [self.phase_NameAndType removeFromSuperview];
    [self.phase_Size removeFromSuperview];
    [self.phase_Position removeFromSuperview];
    [self.phase_Rings removeFromSuperview];
    [self.phase_TextureTemplateAndColor removeFromSuperview];
    
    // Placeholder for the next, upcoming phase view
    UIView *phaseView = nil;
    
    // Show the previous step button. You can always go back (except phase 0)!
    self.previousStepButton.alpha = 1.0f;
    
    // Set the title of the next step button. It only changes on the last phase
    [self.nextStepButton setTitle:@"Next Step" forState:UIControlStateNormal];
    
    if(self.currentPhase == 0) {
        phaseView = self.phase_NameAndType;
        
        // Hide the previous step button because there is no previous step!
        self.previousStepButton.alpha = 0.0f;
        
        // Determine if the next step button should be shown
        self.nextStepButton.alpha = (self.planetNameField.text.length == 0) ? 0.0f : 1.0f;
        
        // Set the title
        self.titleLabel.text = @"Name Your World";
        
    }else if(self.currentPhase == 1) {
        phaseView = self.phase_TextureTemplateAndColor;
        
        // Show the next step button. There will be a default value for this one.
        self.nextStepButton.alpha = 1.0f;
        
        // Set the title
        self.titleLabel.text = @"Design Your World";
        
    }else if(self.currentPhase == 2) {
        phaseView = self.phase_Rings;
        
        // Show the next step button too
        self.nextStepButton.alpha = 1.0f;
        
        // Set the title
        self.titleLabel.text = @"Put A Ring On It?";
        
    }else if(self.currentPhase == 3) {
        phaseView = self.phase_Glow;
        
        // Show the next step button too
        self.nextStepButton.alpha = 1.0f;
        
        // Set the title
        self.titleLabel.text = @"Atmosphere Glow";
        
    }else if(self.currentPhase == 4) {
        phaseView = self.phase_AxisTilt;
        
        // Show the next step button as well. Default values here too
        self.nextStepButton.alpha = 1.0f;
        
        // Set the title
        self.titleLabel.text = @"Axis Tilt";
        
    }else if(self.currentPhase == 5) {
        phaseView = self.phase_Size;
        
        // Show the next step button as well. Default values here too
        self.nextStepButton.alpha = 1.0f;
        
        // Set the title
        self.titleLabel.text = @"World Size";
        
    }else if(self.currentPhase == 6) {
        phaseView = self.phase_Position;
        
        // Show the next step button as well. Default values here too
        self.nextStepButton.alpha = 1.0f;
        
        // Determine if the scrollview needs to be shown
        self.orbitingParentOptionsScrollView.hidden = (self.planetOrMoonControl.selectedSegmentIndex == 0);
        
        // Set the title
        self.titleLabel.text = @"World Position";
        [self.nextStepButton setTitle:@"Save World" forState:UIControlStateNormal];
        
    }
    [self.parentPhaseContainer addSubview:phaseView];
    
    if(self.currentPhase >= 6 || (self.planetOrMoonControl.selectedSegmentIndex == 0 && self.currentPhase >= 4)) {
        [self.nextStepButton setTitle:@"Save World" forState:UIControlStateNormal];
    }
    
    // Possibly introduce the previe view
    if(self.currentPhase > 0) {
        [self.view addSubview:self.previewView];
    }else{
        [self.previewView removeFromSuperview];
    }
}

- (IBAction)didSlideRingColorSlider
{
    CGFloat r = self.ringsColorSliderRed.value;
    CGFloat g = self.ringsColorSliderGreen.value;
    CGFloat b = self.ringsColorSliderBlue.value;
    
    CC3Vector4 color = CC3Vector4Make(r, g, b, 1.0f);
    [self.previewScene setRingColor:color];
}

- (IBAction)didSelectMoonOrPlanet:(UISegmentedControl *)sender
{
    if(sender.selectedSegmentIndex == 0) {
        self.planetNameField.placeholder = @"Planet Name";
        self.planetNameDescription.text = [self.planetNameDescription.text stringByReplacingOccurrencesOfString:@" moon " withString:@" planet "];
        self.orbitingParentOptionsScrollView.hidden = YES;
        self.parentIdentifier = nil;
        self.orbitingParentNameLabel.text = @"Sun";
    }else{
        self.planetNameField.placeholder = @"Moon Name";
        self.planetNameDescription.text = [self.planetNameDescription.text stringByReplacingOccurrencesOfString:@" planet " withString:@" moon "];
        self.orbitingParentOptionsScrollView.hidden = NO;
        self.parentIdentifier = @"earth";
        self.orbitingParentNameLabel.text = @"Earth";
    }
    /*
    self.orbitParentImageView.image = [UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:[NSString stringWithFormat:@"%@-thumb", self.parentIdentifier] ofType:@"png"]];
     */
}

- (IBAction)startSelectingPhotoFromCamera:(UIButton *)sender
{
    [self startSelectingPhoto:UIImagePickerControllerSourceTypeCamera sender:sender];
}

- (IBAction)startSelectingPhotoFromLibrary:(UIButton *)sender
{
    [self startSelectingPhoto:UIImagePickerControllerSourceTypePhotoLibrary sender:sender];
}

- (void)startSelectingPhoto:(UIImagePickerControllerSourceType)type sender:(UIButton *)sender
{
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = type;
    picker.mediaTypes = [NSArray arrayWithObject:(NSString *)kUTTypeImage];
    
    if(type == UIImagePickerControllerSourceTypePhotoLibrary) {
        self.popover = [[UIPopoverController alloc] initWithContentViewController:picker];
        [self.popover presentPopoverFromRect:sender.frame inView:sender.superview permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    }else if(type == UIImagePickerControllerSourceTypeCamera) {
        [self presentViewController:picker animated:YES completion:nil];
    }
}

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    [[UIApplication sharedApplication] setStatusBarHidden:YES];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    UIImage *img = [info objectForKey:UIImagePickerControllerOriginalImage];
    if(img) {
        if(self.currentPhase == 1) {
            Texture *texture = [[Texture alloc] initWithImage:img inView:self.previewView];
            [self.previewScene setPlanetTexture:texture];
            
            self.worldTextureName = nil;
            self.worldTextureImage = img;
        }
    }
    if(picker.sourceType == UIImagePickerControllerSourceTypePhotoLibrary) {
        [self.popover dismissPopoverAnimated:YES];
    }else if(picker.sourceType == UIImagePickerControllerSourceTypeCamera) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (IBAction)didTapCancelButton:(UIButton *)sender
{
    self.cancelAlertView = [[UIAlertView alloc] initWithTitle:@"Exit World Creator" message:@"Are you sure?\rYour world will not be saved." delegate:self cancelButtonTitle:@"Stay" otherButtonTitles:@"Exit", nil];
    [self.cancelAlertView show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if(alertView == self.cancelAlertView) {
        if(buttonIndex != self.cancelAlertView.cancelButtonIndex) {
            // [Texture disposeTexturesFromView:self.previewView];
            [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
        }
        self.cancelAlertView = nil;
    }
}

@end
