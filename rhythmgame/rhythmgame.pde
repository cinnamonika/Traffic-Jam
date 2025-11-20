int gameState = 0;  // 0 = MENU, 1 = GAME //<>// //<>//

// Track which keys are currently held:
boolean dDown = false;
boolean fDown = false;
boolean jDown = false;
boolean kDown = false;

import processing.sound.*;

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

final float NOTE_FADE_TIME_SECONDS = 0.5f;
final float TINT_STRENGTH = 0.5f;

final color[] NOTE_COLORS = new color[]{
  color(255,0,0),
  color(0,255,0),
  color(0,0,255),
  color(255,190,0)
};

SoundFile musicTrack;
TrackData trackData;
SoundFile hitSound;

PImage hitMarkerImage, bgImage;
PImage[] noteImages;
color[] weakNoteColors;
PFont comboFont;

int score = 0;
int comboMultiplier = 1;
int comboUpCounter = 0;
int currentCombo = 0;

ArrayList<ScorePopup> popups = new ArrayList<ScorePopup>();

void setup() {
  size(1012,700,P3D);
  hint(ENABLE_DEPTH_SORT);
  noSmooth();
  
  hitMarkerImage = loadImage("car.png");
  if (hitMarkerImage == null) {
    hitMarkerImage = createImage(64,64,ARGB);
    hitMarkerImage.loadPixels();
    for (int i = 0; i < hitMarkerImage.pixels.length; i++)
      hitMarkerImage.pixels[i] = color(200);
    hitMarkerImage.updatePixels();
  }
  
  bgImage = loadImage("traffic.jpg");
  if (bgImage == null) {
    bgImage = createImage(width, height, ARGB);
    bgImage.loadPixels();
    for (int i = 0; i < bgImage.pixels.length; i++)
      bgImage.pixels[i] = color(20);
    bgImage.updatePixels();
  }
  
  musicTrack = new SoundFile(this, "karma.wav");
  hitSound = new SoundFile(this, "hit.wav");
  
  trackData = new TrackData(dataPath("karmatrack.txt"));
  
  noteImages = new PImage[NUM_NOTE_TYPES];
  weakNoteColors = new color[NUM_NOTE_TYPES];
  for (int i = 0; i < NUM_NOTE_TYPES; i++) {
    weakNoteColors[i] = lerpColor(color(255), NOTE_COLORS[i], TINT_STRENGTH);
    noteImages[i] = createTintedCopy(hitMarkerImage, NOTE_COLORS[i], TINT_STRENGTH);
  }

  comboFont = createFont("Square.ttf", 160);
  textFont(comboFont);
}

void draw() {

  // MENU
  textMode(SHAPE);
  if (gameState == 0) {
    drawMenuScreen();

    if (dDown && fDown && jDown && kDown) {
      startGame();
    }
    return;
  }

  // GAMEPLAY
  background(0);

  pushMatrix();
  hint(DISABLE_DEPTH_TEST);
  tint(255, 40);
  imageMode(CENTER);
  image(bgImage, width/2, height/2, width, height);
  noTint();
  hint(ENABLE_DEPTH_TEST);
  popMatrix();

  detectFailedHits();
  
  float now = musicTrack.position();
  for (int i = popups.size() - 1; i >= 0; --i) {
    ScorePopup p = popups.get(i);
    if (p.isAlive(now)) p.draw(now);
    else popups.remove(i);
  }
  
  drawScore();
  drawTrack();
  drawComboNumber();

  // AUTO RETURN TO MENU WHEN SONG ENDS
  if (!musicTrack.isPlaying()) {
    gameState = 0;
  }
}

void drawMenuScreen() {
  background(0);

  fill(255);
  textAlign(CENTER);

  textSize(60);
  text("Traffic Jam", width/2, height/2 - 40);

  textSize(30);
  text("Hold D + F + J + K to START", width/2, height/2 + 20);
}

void startGame() {
  score = 0;
  comboMultiplier = 1;
  comboUpCounter = 0;
  currentCombo = 0;
  popups.clear();

  for (TrackData.Bar bar : trackData.bars) {
    for (TrackData.Hit hit : bar.hits) {
      hit.state = TrackData.Hit.HIT_PENDING;
      hit.stateTime = 0;
    }
  }

  musicTrack.cue(0);
  musicTrack.play();

  gameState = 1;
}

void drawScore() {
  textSize(30);
  textAlign(LEFT);
  fill(255);
  text("Score: " + score, 10, 30);
  textAlign(RIGHT);
  text(comboMultiplier + "x", width-10, 30);
}

void drawComboNumber() {
  pushStyle();
  textFont(comboFont);
  textSize(140);
  textAlign(RIGHT, CENTER);
  fill(255);
  text(currentCombo, round(width*0.93f), round(height*0.5f));
  popStyle();
}

void detectFailedHits() {
  float playbackPos = musicTrack.position() - trackData.introLength;
  float barLengthSeconds = 60f / (trackData.bpm/4f);

  for (int barIndex = 0; barIndex < trackData.bars.size(); ++barIndex) {
    TrackData.Bar bar = trackData.bars.get(barIndex);
    float barStartSeconds = barIndex * barLengthSeconds;
    
    if (barStartSeconds > playbackPos + OK_TOLERANCE_SECONDS) break;
    if (barStartSeconds + barLengthSeconds < playbackPos - OK_TOLERANCE_SECONDS*2f) continue;
    
    float beatStepSeconds = barLengthSeconds / bar.numBeats;

    for (TrackData.Hit hit : bar.hits) {
      if (hit.state != TrackData.Hit.HIT_PENDING) continue;

      float hitTimeSeconds = barStartSeconds + hit.beat*beatStepSeconds;

      if (playbackPos - hitTimeSeconds > OK_TOLERANCE_SECONDS) {
        hit.state = TrackData.Hit.HIT_FAILURE;
        hit.stateTime = musicTrack.position();
        comboMultiplier = 1;
        comboUpCounter = 0;
        currentCombo = 0;
        popups.add(new ScorePopup("CRASH...", width/2, height*0.65, color(120)));
      }
    }
  }
}

void drawTrack() {
  pushMatrix();
  translate(width/2, height*0.75f);
  rotateX(0.70f);
  scale(TRACK_SCALE);

  // Track background
  noStroke();
  fill(30);
  float trackWidth = LANE_SPACING_PIXELS * NUM_NOTE_TYPES;
  rectMode(CENTER);
  rect(0, 0, trackWidth, BAR_LENGTH_PIXELS * 4); // centered

  // Lane dividers
  hint(DISABLE_DEPTH_TEST);
  stroke(255);
  strokeWeight(6);
  float dashLength = 40;
  float dashGap = 30;
  float leftEdge = -trackWidth/2;
  for (int i = 1; i < NUM_NOTE_TYPES; i++) {
    float x = leftEdge + i * LANE_SPACING_PIXELS;
    for (float y = -BAR_LENGTH_PIXELS * 2; y < BAR_LENGTH_PIXELS * 2; y += dashLength + dashGap) {
      line(x, y, x, y + dashLength);
    }
  }
  
  float leftBorderX = -trackWidth/2;
  float rightBorderX = trackWidth/2;
  line(leftBorderX, -BAR_LENGTH_PIXELS*2, leftBorderX, BAR_LENGTH_PIXELS*2);
  line(rightBorderX, -BAR_LENGTH_PIXELS*2, rightBorderX, BAR_LENGTH_PIXELS*2);

  // Draw notes
  float playbackPos = musicTrack.position();
  float barLengthSeconds = 60f / (trackData.bpm/4f);
  float offsetY = ((playbackPos - trackData.introLength) / barLengthSeconds) * BAR_LENGTH_PIXELS;

  imageMode(CENTER);
  blendMode(ADD);
  hint(DISABLE_DEPTH_TEST);

  for (int barIndex = 0; barIndex < trackData.bars.size(); ++barIndex) {
    TrackData.Bar bar = trackData.bars.get(barIndex);
    float beatStepY = -BAR_LENGTH_PIXELS / bar.numBeats;
    float barStartY = -BAR_LENGTH_PIXELS * barIndex + offsetY;

    float cullMargin = BAR_LENGTH_PIXELS * 3;
    if (barStartY > cullMargin) continue;
    if (barStartY < -cullMargin * 2) break;

    for (TrackData.Hit hit : bar.hits) {
      float hitX = leftEdge + hit.note * LANE_SPACING_PIXELS + LANE_SPACING_PIXELS/2;
      float hitY = barStartY + hit.beat * beatStepY;

      switch (hit.state) {
        case TrackData.Hit.HIT_PENDING:
          image(noteImages[hit.note], hitX, hitY);
          break;

        case TrackData.Hit.HIT_FAILURE:
        case TrackData.Hit.HIT_SUCCESS: {
          float timeSinceHit = playbackPos - hit.stateTime;
          float alphaFactor = max(1f - timeSinceHit / NOTE_FADE_TIME_SECONDS, 0f);
          tint(255, alphaFactor * 255);
          image(noteImages[hit.note], hitX, hitY);
          noTint();
          break;
        }
      }
    }
  }

  popMatrix();
  
  hint(DISABLE_DEPTH_TEST);
  strokeWeight(4);
  stroke(255);

  int noteHeight = hitMarkerImage.height;
  int judgeTop = round(height * 0.75f) - noteHeight/2;
  int judgeBottom = round(height * 0.75f) + noteHeight/2;

  line(0, judgeTop, width, judgeTop);
  line(0, judgeBottom, width, judgeBottom);

  noStroke();
  fill(255, 15);
  rectMode(CORNER);
  rect(0, judgeTop, width, judgeBottom - judgeTop);
  rectMode(CENTER);

  hint(ENABLE_DEPTH_TEST);

}

void keyPressed() {
  // Track held states
  if (key == 'd' || key == 'D') dDown = true;
  if (key == 'f' || key == 'F') fDown = true;
  if (key == 'j' || key == 'J') jDown = true;
  if (key == 'k' || key == 'K') kDown = true;
  
  // Only gameplay hits when running
  if (gameState != 1) return;

  int note;
  if      (key == 'd' || key == 'D') note = 0;
  else if (key == 'f' || key == 'F') note = 1;
  else if (key == 'j' || key == 'J') note = 2;
  else if (key == 'k' || key == 'K') note = 3;
  else return;

  handleHit(note);
}

void keyReleased() {
  if (key == 'd' || key == 'D') dDown = false;
  if (key == 'f' || key == 'F') fDown = false;
  if (key == 'j' || key == 'J') jDown = false;
  if (key == 'k' || key == 'K') kDown = false;
}

void handleHit(int note) {
  float playbackPos = musicTrack.position() - trackData.introLength;
  TrackData.Hit matchedHit = null;
  float barLengthSeconds = 60f / (trackData.bpm/4f);
  
  for (int barIndex = 0; barIndex < trackData.bars.size(); ++barIndex) {
    TrackData.Bar bar = trackData.bars.get(barIndex);
    float barStartSeconds = barIndex * barLengthSeconds;
    
    if (barStartSeconds > playbackPos + OK_TOLERANCE_SECONDS) break;
    if (barStartSeconds + barLengthSeconds < playbackPos - OK_TOLERANCE_SECONDS) continue;
    
    float beatStepSeconds = barLengthSeconds / bar.numBeats;
    for (TrackData.Hit hit : bar.hits) {
      if (hit.state != TrackData.Hit.HIT_PENDING) continue;
      if (hit.note != note) continue;

      float hitTimeSeconds = barStartSeconds + hit.beat * beatStepSeconds;
      float timeDiff = abs(hitTimeSeconds - playbackPos);

      if (timeDiff < PERFECT_TOLERANCE_SECONDS) {
        score += PERFECT_SCORE * comboMultiplier;
        matchedHit = hit;
        currentCombo++;
        popups.add(new ScorePopup("GREEN!", width/2, height*0.65, color(4,214,0)));
        break;
      } 
      else if (timeDiff < GREAT_TOLERANCE_SECONDS) {
        score += GREAT_SCORE * comboMultiplier;
        matchedHit = hit;
        currentCombo++;
        popups.add(new ScorePopup("YELLOW!", width/2, height*0.65, color(255,184,41)));
        break;
      }
      else if (timeDiff < OK_TOLERANCE_SECONDS) {
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

PImage createTintedCopy(PImage src, color tintColor, float strength) {
  PImage out = createImage(src.width, src.height, ARGB);
  src.loadPixels();
  out.loadPixels();
  for (int i = 0; i < src.pixels.length; i++) {
    int pix = src.pixels[i];
    float a = alpha(pix);
    float r0 = red(pix), g0 = green(pix), b0 = blue(pix);
    float rt = red(tintColor), gt = green(tintColor), bt = blue(tintColor);
    float r = r0 * (1 - strength) + rt * strength;
    float g = g0 * (1 - strength) + gt * strength;
    float b = b0 * (1 - strength) + bt * strength;
    out.pixels[i] = color(constrain(r,0,255), constrain(g,0,255), constrain(b,0,255), a);
  }
  out.updatePixels();
  return out;
}
