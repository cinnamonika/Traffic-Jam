import processing.sound.*; //<>//

// Timing / gameplay-related constants
final int NUM_NOTE_TYPES = 4;
final float PERFECT_TOLERANCE_SECONDS = 0.05f;
final float GREAT_TOLERANCE_SECONDS = 0.1f;
final float OK_TOLERANCE_SECONDS = 0.2f;

final int PERFECT_SCORE = 100;
final int GREAT_SCORE = 50;
final int OK_SCORE = 20;

final int COMBO_UP_INTERVAL = 10;
final int COMBO_MAX_MULTIPLIER = 10;

// Audio-visual-related constants
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

// Assets
SoundFile musicTrack;
TrackData trackData;
SoundFile hitSound;

PImage hitMarkerImage, bgImage;

PImage[] noteImages;
color[] weakNoteColors;
PFont comboFont;

// State
int score = 0;
int comboMultiplier = 1;
int comboUpCounter = 0;
int currentCombo = 0;

// Popups
ArrayList<ScorePopup> popups = new ArrayList<ScorePopup>();

void setup() {
  size(1012,700,P3D);
  hint(ENABLE_DEPTH_SORT);
  noSmooth(); // We can remove this if it runs smoothly without it at the end
  
  // Load note image
  hitMarkerImage = loadImage("car.png");
  if (hitMarkerImage == null) {
    println("hitMarkerImage not found in data folder.");
    hitMarkerImage = createImage(64,64,ARGB);
    hitMarkerImage.loadPixels();
    for (int i = 0; i < hitMarkerImage.pixels.length; i++) hitMarkerImage.pixels[i] = color(200);
    hitMarkerImage.updatePixels();
  }
  
  // Load background
  bgImage = loadImage("traffic.jpg");
  if (bgImage == null) {
    println("bgImage not found in data folder.");
    bgImage = createImage(width, height, ARGB);
    bgImage.loadPixels();
    for (int i = 0; i < bgImage.pixels.length; i++) bgImage.pixels[i] = color(20);
    bgImage.updatePixels();
  }
  
  // Load audio file
  musicTrack = new SoundFile(this, "karma.wav");
  hitSound = new SoundFile(this, "hit.wav");
  
  // Load track data
  trackData = new TrackData(dataPath("karmatrack.txt"));
  
  noteImages = new PImage[NUM_NOTE_TYPES];
  weakNoteColors = new color[NUM_NOTE_TYPES];
  for (int i = 0; i < NUM_NOTE_TYPES; i++) {
    weakNoteColors[i] = lerpColor(color(255,255,255), NOTE_COLORS[i], TINT_STRENGTH);
    noteImages[i] = createTintedCopy(hitMarkerImage, NOTE_COLORS[i], TINT_STRENGTH);
  }

  comboFont = createFont("Square.ttf", 160, true);
  textFont(comboFont);
  
  musicTrack.play();
}

void draw() {
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
}

void drawScore() {
  textSize(30);
  textAlign(LEFT);
  fill(255);
  text("Score: " + score, 10, 30);
  textAlign(RIGHT);
  text(comboMultiplier+"x", width-10, 30);
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

void detectFailedHits() {
  float playbackPos = musicTrack.position() - trackData.introLength;
  float barLengthSeconds = 60f / (trackData.bpm/4f);
  for (int barIndex = 0; barIndex < trackData.bars.size(); ++barIndex) {
    TrackData.Bar bar = trackData.bars.get(barIndex);
    float barStartSeconds = barIndex * barLengthSeconds;
    
    if (barStartSeconds > playbackPos + OK_TOLERANCE_SECONDS) break;
    if (barStartSeconds + barLengthSeconds < playbackPos - OK_TOLERANCE_SECONDS*2.0f) continue;
    
    float beatStepSeconds = barLengthSeconds / bar.numBeats;
    for (TrackData.Hit hit : bar.hits) {
      if (hit.state != TrackData.Hit.HIT_PENDING) continue;
      float hitTimeSeconds = barStartSeconds + hit.beat*beatStepSeconds;
      if (playbackPos - hitTimeSeconds > OK_TOLERANCE_SECONDS) {
        hit.state = TrackData.Hit.HIT_FAILURE;
        hit.stateTime = musicTrack.position() - trackData.introLength;
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
  
  float playbackPos = musicTrack.position();
  float barStartX = -LANE_SPACING_PIXELS*(NUM_NOTE_TYPES-1)*0.5f;  
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
    
    noFill();

    for (TrackData.Hit hit : bar.hits) {
      float hitX = barStartX + hit.note*LANE_SPACING_PIXELS;
      float hitY = barStartY + hit.beat*beatStepY;
      
      switch (hit.state) {
        case TrackData.Hit.HIT_PENDING:
          image(noteImages[hit.note], hitX, hitY);
          break;
          
        case TrackData.Hit.HIT_FAILURE: {
          float timeSinceHit = playbackPos - hit.stateTime;
          float alphaFactor = Math.max(1f - timeSinceHit / NOTE_FADE_TIME_SECONDS, 0f);
          tint(255, alphaFactor * 255);
          image(noteImages[hit.note], hitX, hitY);
          noTint();
          break;
        }
        case TrackData.Hit.HIT_SUCCESS: {
          float timeSinceHit = playbackPos - hit.stateTime;
          float alphaFactor = Math.max(1f - timeSinceHit / NOTE_FADE_TIME_SECONDS, 0f);
          tint(255, alphaFactor * 255);
          image(noteImages[hit.note], hitX, hitY);
          noTint();
          break;
        }
      }
    }
  }

  hint(ENABLE_DEPTH_TEST);
  blendMode(NORMAL);

  popMatrix();
  
  int noteHeight = hitMarkerImage.height;
  int centerY = round(height * 0.75f);
  int judgeTop = centerY - noteHeight/2;
  int judgeBottom = centerY + noteHeight/2;

  stroke(255);

  line(0, judgeTop, width, judgeTop);
  line(0, judgeBottom, width, judgeBottom);
  
  noStroke();
  fill(255, 255, 255, 15);
  rect(0, judgeTop, width, (judgeBottom - judgeTop));
}

void keyPressed() {
  int note;
  if (key == 'd' || key == 'D') note = 0;
  else if (key == 'f' || key == 'F') note = 1;
  else if (key == 'j' || key == 'J') note = 2;
  else if (key == 'k' || key == 'K') note = 3;
  else return;
  
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
      float hitTimeSeconds = barStartSeconds + hit.beat*beatStepSeconds;
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
        popups.add(new ScorePopup("YELLOW!", width/2, height*0.65, color(255, 184, 41)));
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
    ++comboUpCounter;
    if (comboUpCounter == COMBO_UP_INTERVAL) {
      comboMultiplier = min(COMBO_MAX_MULTIPLIER, comboMultiplier + 1);
      comboUpCounter = 0;
    }
  } else {
    boolean nearNote = false;
    barLengthSeconds = 60f / (trackData.bpm/4f);
    for (int barIndex = 0; barIndex < trackData.bars.size(); ++barIndex) {
      TrackData.Bar bar = trackData.bars.get(barIndex);
      float barStartSeconds = barIndex * barLengthSeconds;

      float beatStepSeconds = barLengthSeconds / bar.numBeats;
      for (TrackData.Hit hit : bar.hits) {
        if (hit.state != TrackData.Hit.HIT_PENDING) continue;

        float hitTimeSeconds = barStartSeconds + hit.beat * beatStepSeconds;
        float timeDiff = abs(hitTimeSeconds - playbackPos);

        if (timeDiff < OK_TOLERANCE_SECONDS) {
          nearNote = true;
          break;
        }
      }
      if (nearNote) break;
    }
    if (nearNote) {
      currentCombo = 0;
    }
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
