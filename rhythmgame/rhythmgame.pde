/* ============================================================ //<>//
   GLOBALS + SETUP (JAVA2D VERSION)
   ============================================================ */

int gameState = 0;  // 0 = MENU, 1 = GAME

// GPIO pins
int PIN_D = 576;
int PIN_F = 577;
int PIN_J = 593;
int PIN_K = 598;

import processing.io.*;
import processing.sound.*;

// GAME CONSTANTS
final int NUM_NOTE_TYPES = 4;
final float PERFECT_TOLERANCE_SECONDS = 0.05f;
final float GREAT_TOLERANCE_SECONDS = 0.1f;
final float OK_TOLERANCE_SECONDS = 0.2f;

final int PERFECT_SCORE = 100;
final int GREAT_SCORE = 50;
final int OK_SCORE = 20;

final int COMBO_UP_INTERVAL = 10;
final int COMBO_MAX_MULTIPLIER = 10;

final float BAR_LENGTH_PIXELS = 1800f;
final float LANE_SPACING_PIXELS = 150f;
final float TRACK_SCALE = 1.25f;

// 2D tilt config
final float TILT = 0.60f;       // slightly less tilt
final float COS_TILT = cos(TILT);

// (When tilting around judge line, we ONLY compress Y)
float projectY(float y) {
  return y * COS_TILT;
}

final float NOTE_FADE_TIME_SECONDS = 0.5f;
final float TINT_STRENGTH = 0.5f;

final color[] NOTE_COLORS = {
  color(255,0,0),
  color(0,255,0),
  color(0,0,255),
  color(255,190,0)
};

// ASSETS
SoundFile musicTrack;
TrackData trackData;
SoundFile hitSound;

PImage hitMarkerImage, bgImage;
PImage[] noteImages;
color[] weakNoteColors;
PFont comboFont;

// Score + Combo
int score = 0;
int comboMultiplier = 1;
int comboUpCounter = 0;
int currentCombo = 0;

ArrayList<ScorePopup> popups = new ArrayList<ScorePopup>();

/* ============================================================
   SETUP (NO P3D)
   ============================================================ */

void setup() {
  // *** IMPORTANT ***
  // No P3D — Java2D only
  fullScreen();

  noSmooth();

  // GPIO pins
  GPIO.pinMode(PIN_D, GPIO.INPUT);
  GPIO.pinMode(PIN_F, GPIO.INPUT);
  GPIO.pinMode(PIN_J, GPIO.INPUT);
  GPIO.pinMode(PIN_K, GPIO.INPUT);

  hitMarkerImage = loadImage("car.png");
  if (hitMarkerImage == null) {
    hitMarkerImage = createImage(64,64,ARGB);
    hitMarkerImage.loadPixels();
    for (int i = 0; i < hitMarkerImage.pixels.length; i++)
      hitMarkerImage.pixels[i] = color(200);
    hitMarkerImage.updatePixels();
  }

  // simple bg fallback
  bgImage = createImage(width, height, ARGB);
  bgImage.loadPixels();
  for (int i = 0; i < bgImage.pixels.length; i++)
    bgImage.pixels[i] = color(20);
  bgImage.updatePixels();

  // Sounds
  musicTrack = new SoundFile(this, "karma.wav");
  hitSound = new SoundFile(this, "hit.wav");

  // Track data
  trackData = new TrackData(dataPath("karmatrack.txt"));

  // Note colors
  noteImages = new PImage[NUM_NOTE_TYPES];
  weakNoteColors = new color[NUM_NOTE_TYPES];
  for (int i = 0; i < NUM_NOTE_TYPES; i++) {
    weakNoteColors[i] = lerpColor(color(255), NOTE_COLORS[i], TINT_STRENGTH);
    noteImages[i] = createTintedCopy(hitMarkerImage, NOTE_COLORS[i], TINT_STRENGTH);
  }

  comboFont = createFont("Square.ttf", 160);
}

/* ============================================================
   BUTTON INPUT
   ============================================================ */

boolean buttonD() { return GPIO.digitalRead(PIN_D) == GPIO.LOW; }
boolean buttonF() { return GPIO.digitalRead(PIN_F) == GPIO.LOW; }
boolean buttonJ() { return GPIO.digitalRead(PIN_J) == GPIO.LOW; }
boolean buttonK() { return GPIO.digitalRead(PIN_K) == GPIO.LOW; }

/* ============================================================
   MAIN DRAW LOOP
   ============================================================ */

void draw() {

  // MENU
  if (gameState == 0) {
    drawMenuScreen();

    if (buttonD() && buttonF() && buttonJ() && buttonK()) {
      startGame();
    }
    return;
  }

  // GAMEPLAY
  background(0);

  // Background image
  tint(255, 40);
  imageMode(CORNER);
  image(bgImage, 0, 0, width, height);
  noTint();

  detectFailedHits();

  float now = musicTrack.position();

  // popups
  for (int i = popups.size() - 1; i >= 0; --i) {
    ScorePopup p = popups.get(i);
    if (p.isAlive(now)) p.draw(now);
    else popups.remove(i);
  }

  drawScore();
  drawTrack();      // <-- Fully rewritten in PART 3/4
  drawComboNumber();

  // End of song
  if (!musicTrack.isPlaying()) {
    gameState = 0;
  }

  // Input
  if (buttonD()) handleHit(0);
  if (buttonF()) handleHit(1);
  if (buttonJ()) handleHit(2);
  if (buttonK()) handleHit(3);
}

/* ============================================================
   MENU
   ============================================================ */

void drawMenuScreen() {
  background(0);

  fill(255);
  textAlign(CENTER);

  textSize(60);
  text("Traffic Jam", width/2, height/2 - 40);

  textSize(30);
  text("Hold ALL 4 BUTTONS to START", width/2, height/2 + 20);
}

void startGame() {
  score = 0;
  comboMultiplier = 1;
  comboUpCounter = 0;
  currentCombo = 0;
  popups.clear();

  for (TrackData.Bar bar : trackData.bars)
    for (TrackData.Hit hit : bar.hits) {
      hit.state = TrackData.Hit.HIT_PENDING;
      hit.stateTime = 0;
    }

  musicTrack.cue(0);
  musicTrack.play();
  gameState = 1;
}


/* ============================================================
   SCORE + COMBO
   ============================================================ */

void drawScore() {
  textSize(30);
  textAlign(LEFT);
  fill(255);
  text("Score: " + score, 10, 30);

  textAlign(RIGHT);
  text(comboMultiplier + "x", width - 10, 30);
}

void drawComboNumber() {
  pushStyle();
  textFont(comboFont);
  textSize(140);
  textAlign(RIGHT, CENTER);
  fill(255);
  text(currentCombo, round(width * 0.93f), round(height * 0.5f));
  popStyle();
}

/* ============================================================
   FAILED HIT DETECTION
   ============================================================ */

void detectFailedHits() {
  float playbackPos = musicTrack.position() - trackData.introLength;
  float barLengthSeconds = 60f / (trackData.bpm / 4f);

  for (int barIndex = 0; barIndex < trackData.bars.size(); ++barIndex) {

    TrackData.Bar bar = trackData.bars.get(barIndex);
    float barStartSeconds = barIndex * barLengthSeconds;

    if (barStartSeconds > playbackPos + OK_TOLERANCE_SECONDS) break;
    if (barStartSeconds + barLengthSeconds < playbackPos - OK_TOLERANCE_SECONDS * 2f) continue;

    float beatStepSeconds = barLengthSeconds / bar.numBeats;

    for (TrackData.Hit hit : bar.hits) {
      if (hit.state != TrackData.Hit.HIT_PENDING) continue;

      float hitTimeSeconds = barStartSeconds + hit.beat * beatStepSeconds;

      if (playbackPos - hitTimeSeconds > OK_TOLERANCE_SECONDS) {
        hit.state = TrackData.Hit.HIT_FAILURE;
        hit.stateTime = musicTrack.position();

        comboMultiplier = 1;
        comboUpCounter = 0;
        currentCombo = 0;

        popups.add(new ScorePopup("CRASH...", width / 2, height * 0.65, color(120)));
      }
    }
  }
}

/* ============================================================
   HIT LOGIC (unchanged gameplay)
   ============================================================ */

void handleHit(int note) {
  float playbackPos = musicTrack.position() - trackData.introLength;
  TrackData.Hit matchedHit = null;

  float barLengthSeconds = 60f / (trackData.bpm / 4f);

  for (int barIndex = 0; barIndex < trackData.bars.size(); ++barIndex) {

    TrackData.Bar bar = trackData.bars.get(barIndex);
    float barStartSeconds = barIndex * barLengthSeconds;

    if (barStartSeconds > playbackPos + OK_TOLERANCE_SECONDS) break;
    if (barStartSeconds + barLengthSeconds < playbackPos - OK_TOLERANCE_SECONDS) continue;

    float beatStepSeconds = barLengthSeconds / bar.numBeats;

    for (TrackData.Hit hit : bar.hits) {
      if (hit.state != TrackData.Hit.HIT_PENDING) continue;
      if (hit.note != note) continue;

      float hitTime = barStartSeconds + hit.beat * beatStepSeconds;
      float diff = abs(hitTime - playbackPos);

      if (diff < PERFECT_TOLERANCE_SECONDS) {
        score += PERFECT_SCORE * comboMultiplier;
        matchedHit = hit;
        currentCombo++;
        popups.add(new ScorePopup("GREEN!", width/2, height*0.65, color(4,214,0)));
        break;
      }
      else if (diff < GREAT_TOLERANCE_SECONDS) {
        score += GREAT_SCORE * comboMultiplier;
        matchedHit = hit;
        currentCombo++;
        popups.add(new ScorePopup("YELLOW!", width/2, height*0.65, color(255,184,41)));
        break;
      }
      else if (diff < OK_TOLERANCE_SECONDS) {
        score += OK_SCORE * comboMultiplier;
        matchedHit = hit;
        currentCombo++;
        popups.add(new ScorePopup("RED", width/2, height*0.65, color(214,0,25)));
        break;
      }
    }
  }

  if (matchedHit != null) {
    matchedHit.state = TrackData.Hit.HIT_SUCCESS;
    matchedHit.stateTime = musicTrack.position();
    hitSound.play();

    comboUpCounter++;
    if (comboUpCounter == COMBO_UP_INTERVAL) {
      comboMultiplier = min(COMBO_MAX_MULTIPLIER, comboMultiplier + 1);
      comboUpCounter = 0;
    }

  } else {
    currentCombo = 0;
  }
}

/* ============================================================
   SCORE POPUP CLASS (unchanged, Java2D safe)
   ============================================================ */

class ScorePopup {
  String text;
  float x, y;
  float startTime;
  float duration = 0.6f;
  float rise = 40;
  color col;

  ScorePopup(String text, float x, float y, color col) {
    this.text = text;
    this.x = x;
    this.y = y;
    this.col = col;
    startTime = musicTrack.position();
  }

  boolean isAlive(float now) {
    return now - startTime < duration;
  }

  void draw(float now) {
    float t = (now - startTime) / duration;
    float alpha = 255 * (1 - t);
    float dy = lerp(0, -rise, t);

    fill(red(col), green(col), blue(col), alpha);
    textAlign(CENTER);
    textSize(40);
    text(text, x, y + dy);
  }
}


/* ============================================================
   TRACK RENDERING (JAVA2D TILTED VERSION)
   ============================================================ */

void drawTrack() {

  // Where the judge line sits on screen
  float judgeY_screen = height;

  // Track width in unprojected space
  float trackWidth = LANE_SPACING_PIXELS * NUM_NOTE_TYPES;
  float leftEdge = -trackWidth / 2;

  // Playback position
  float playbackPos = musicTrack.position();
  float barLengthSec = 60f / (trackData.bpm / 4f);

  // Offset along track (positive = closer)
  float offsetY = ((playbackPos - trackData.introLength) / barLengthSec) * BAR_LENGTH_PIXELS;

  /* ------------------------------------------------------------
     1. DRAW TRACK BASE (dark rectangle)
     ------------------------------------------------------------ */

  noStroke();
  fill(30);

  // Unprojected track body (centered on x = width/2)
  float X0 = width / 2 + leftEdge;
  float X1 = width / 2 + leftEdge + trackWidth;

  // Track depth extends far above judge line
  float trackDepth = BAR_LENGTH_PIXELS * 4;

  // Project the top and bottom edges
  float Y_bottom = projectY(0);
  float Y_top = projectY(-trackDepth);

  rectMode(CORNERS);
  rect(X0, judgeY_screen + Y_top, X1, judgeY_screen + Y_bottom);

  /* ------------------------------------------------------------
     2. LANE DIVIDERS
     ------------------------------------------------------------ */

  stroke(255);
  strokeWeight(4);

  for (int i = 1; i < NUM_NOTE_TYPES; i++) {
    float baseX = width/2 + leftEdge + i*LANE_SPACING_PIXELS;

    // vertical divider from far to near
    float yA = judgeY_screen + projectY(-trackDepth);
    float yB = judgeY_screen + projectY(0);

    line(baseX, yA, baseX, yB);
  }

  // Edge borders
  float Lx = width/2 + leftEdge;
  float Rx = width/2 + leftEdge + trackWidth;

  float Yfar = judgeY_screen + projectY(-trackDepth);
  float Ynear = judgeY_screen + projectY(0);

  line(Lx, Yfar, Lx, Ynear);
  line(Rx, Yfar, Rx, Ynear);

  /* ------------------------------------------------------------
     3. DRAW NOTES
     ------------------------------------------------------------ */

  imageMode(CENTER);

  for (int barIndex = 0; barIndex < trackData.bars.size(); ++barIndex) {
    TrackData.Bar bar = trackData.bars.get(barIndex);

    float beatStepY = -BAR_LENGTH_PIXELS / bar.numBeats;
    float barStartY = -BAR_LENGTH_PIXELS * barIndex + offsetY;

    float cullMargin = BAR_LENGTH_PIXELS * 3;
    if (barStartY > cullMargin) continue;
    if (barStartY < -cullMargin * 2) break;

    for (TrackData.Hit hit : bar.hits) {

      float noteX_unproj =
        width/2 + leftEdge + hit.note*LANE_SPACING_PIXELS + LANE_SPACING_PIXELS/2;

      float noteY_unproj = barStartY + hit.beat * beatStepY;

      // PROJECT Y (constant-size notes)
      float noteY_proj = judgeY_screen + projectY(noteY_unproj);

      switch (hit.state) {

      case TrackData.Hit.HIT_PENDING:
        image(noteImages[hit.note], noteX_unproj, noteY_proj);
        break;

      case TrackData.Hit.HIT_FAILURE:
      case TrackData.Hit.HIT_SUCCESS:
        float t = max(0, 1 - (playbackPos - hit.stateTime) / NOTE_FADE_TIME_SECONDS);
        tint(255, t * 255);
        image(noteImages[hit.note], noteX_unproj, noteY_proj);
        noTint();
        break;
      }
    }
  }

  /* ------------------------------------------------------------
     4. JUDGE LINES (flat, not projected)
     ------------------------------------------------------------ */

  int noteHeight = hitMarkerImage.height;
  int judgeTop = round(judgeY_screen - noteHeight/2);
  int judgeBottom = round(judgeY_screen + noteHeight/2);

  stroke(255);
  strokeWeight(3);
  line(0, judgeTop, width, judgeTop);
  line(0, judgeBottom, width, judgeBottom);

  noStroke();
  fill(255, 15);
  rectMode(CORNER);
  rect(0, judgeTop, width, judgeBottom - judgeTop);
}
/* ============================================================
   IMAGE TINT (unchanged, Java2D safe)
   ============================================================ */

PImage createTintedCopy(PImage src, color tintColor, float strength) {
  PImage out = createImage(src.width, src.height, ARGB);
  src.loadPixels();
  out.loadPixels();

  float rt = red(tintColor);
  float gt = green(tintColor);
  float bt = blue(tintColor);

  for (int i = 0; i < src.pixels.length; i++) {
    int pix = src.pixels[i];

    float a = alpha(pix);
    float r0 = red(pix);
    float g0 = green(pix);
    float b0 = blue(pix);
  
    float r = r0 * (1 - strength) + rt * strength;
    float g = g0 * (1 - strength) + gt * strength;
    float b = b0 * (1 - strength) + bt * strength;

    out.pixels[i] = color(constrain(r, 0, 255),
                          constrain(g, 0, 255),
                          constrain(b, 0, 255),
                          a);
  }

  out.updatePixels();
  return out;
}
