package io.rapidpro.mage.test;

import com.google.common.io.CharStreams;
import org.junit.Ignore;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.InputStreamReader;

/**
 * Base class for all unit tests
 */
@Ignore
public abstract class BaseMageTest {

    protected final Logger log = LoggerFactory.getLogger(getClass());

    protected String loadResource(String path) throws Exception {
        InputStreamReader in = new InputStreamReader(getClass().getClassLoader().getResourceAsStream(path));
        return CharStreams.toString(in);
    }
}