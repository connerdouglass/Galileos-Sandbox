//
//  WorldCreatorViewController.h
//  Galileo's Sandbox
//
//  Created by Conner Douglass on 6/4/14.
//  Copyright (c) 2014 Conner Douglass. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface WorldCreatorViewController : UIViewController

+ (void)saveUserWorldWithDictionary:(NSDictionary *)worldDictionary;
+ (BOOL)worldExistsWithKey:(NSString *)key value:(NSString *)value;

@property NSString *existingWorldIdentifier;

@property IBOutlet UIButton *cancelButton;
@property IBOutlet UIButton *nextStepButton;
@property IBOutlet UIButton *previousStepButton;
@property IBOutlet UILabel *titleLabel;

@property IBOutlet UIView *parentPhaseContainer;

@property IBOutlet UIView *phase_NameAndType;
@property IBOutlet UITextField *planetNameField;
@property IBOutlet UISegmentedControl *planetOrMoonControl;
@property IBOutlet UILabel *planetNameDescription;

@property IBOutlet UIView *phase_TextureTemplateAndColor;
@property IBOutlet UIScrollView *textureTemplateSelectionScrollView;

@property IBOutlet UIView *phase_Rings;
@property IBOutlet UIScrollView *ringsStylesSelectionScrollView;
@property IBOutlet UISlider *ringsColorSliderRed;
@property IBOutlet UISlider *ringsColorSliderGreen;
@property IBOutlet UISlider *ringsColorSliderBlue;
@property IBOutlet UISlider *ringsColorSliderAlpha;

@property IBOutlet UIView *phase_AxisTilt;
@property IBOutlet UISlider *axialTiltSlider;
@property IBOutlet UILabel *axialTiltValueLabel;

@property IBOutlet UIView *phase_Size;
@property IBOutlet UISlider *radiusSlider;

@property IBOutlet UIView *phase_Position;
@property IBOutlet UISlider *orbitDistance;
@property IBOutlet UILabel *orbitingParentDescLabel;
@property IBOutlet UILabel *orbitingParentNameLabel;
@property IBOutlet UIScrollView *orbitingParentOptionsScrollView;
@property NSString *parentIdentifier;

@property IBOutlet UIView *phase_Glow;
@property IBOutlet UISlider *glowSliderRed;
@property IBOutlet UISlider *glowSliderGreen;
@property IBOutlet UISlider *glowSliderBlue;
@property IBOutlet UISwitch *glowEnabled;

@property IBOutlet UIView *toolbarBackgroundView;

- (void)loadDataForIdentifier:(NSString *)identifier;

@end